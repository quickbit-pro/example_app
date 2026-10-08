/* Standalone browser helpers. No network, package, or build dependencies. */
(function installBrandGuideFiles(root) {
  "use strict";

  const encoder = new TextEncoder();
  const MAX_ZIP_VALUE = 0xfffffffe; // 0xffffffff is reserved for ZIP64.
  const MAX_ZIP_ENTRIES = 0xfffe; // 0xffff is reserved for ZIP64.
  const MAX_IMPORT_BYTES = 100 * 1024 * 1024;
  const BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const ALLOWED_ASSET_EXTENSIONS = new Set([
    "png", "jpg", "jpeg", "webp", "gif", "ttf", "otf", "txt", "json", "plist",
  ]);
  const crcTable = new Uint32Array(256);
  for (let value = 0; value < 256; value += 1) {
    let crc = value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    crcTable[value] = crc >>> 0;
  }

  function requireBytes(bytes) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("File data must be a Uint8Array.");
    }
    return bytes;
  }

  function crc32(bytes) {
    let crc = 0xffffffff;
    for (let index = 0; index < bytes.length; index += 1) {
      crc = (crc >>> 8) ^ crcTable[(crc ^ bytes[index]) & 0xff];
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function validPath(name) {
    if (typeof name !== "string" || name.length === 0) {
      throw new TypeError("Each ZIP entry needs a nonempty relative file path.");
    }
    if (/^[\/\\]/.test(name) || /[\\:\u0000-\u001f\u007f]/.test(name)) {
      throw new Error("Unsafe ZIP path: absolute paths, backslashes, colons, and control characters are not allowed.");
    }
    const parts = name.split("/");
    if (parts.some((part) => part === "" || part === "." || part === "..")) {
      throw new Error("Unsafe ZIP path: empty, dot, and parent-directory segments are not allowed.");
    }
    // TextEncoder silently replaces lone surrogates; reject them to preserve names exactly.
    for (let index = 0; index < name.length; index += 1) {
      const code = name.charCodeAt(index);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = name.charCodeAt(index + 1);
        if (!(next >= 0xdc00 && next <= 0xdfff)) {
          throw new Error("ZIP paths must contain valid Unicode characters.");
        }
        index += 1;
      } else if (code >= 0xdc00 && code <= 0xdfff) {
        throw new Error("ZIP paths must contain valid Unicode characters.");
      }
    }
    const encoded = encoder.encode(name);
    if (encoded.length > 0xffff) {
      throw new RangeError("ZIP entry names cannot exceed 65,535 UTF-8 bytes.");
    }
    return { parts, encoded };
  }

  function registerPath(name, files, directories) {
    const { parts, encoded } = validPath(name);
    if (files.has(name)) throw new Error("Duplicate ZIP entry: " + name);
    // A trie keeps validation linear in path length, even for deeply nested names.
    let current = directories;
    for (let index = 0; index < parts.length; index += 1) {
      const part = parts[index];
      let node = current.get(part);
      if (!node) {
        node = { file: false, children: new Map() };
        current.set(part, node);
      }
      const isLast = index === parts.length - 1;
      if (node.file || (isLast && node.children.size > 0)) {
        throw new Error("ZIP path is used as both a file and a directory: " + parts.slice(0, index + 1).join("/"));
      }
      if (isLast) node.file = true;
      current = node.children;
    }
    files.add(name);
    return encoded;
  }

  /**
   * Build a deterministic, uncompressed (STORE) UTF-8 ZIP archive.
   * Entries are { name: relativePath, bytes: Uint8Array | string }.
   * ZIP64, directory entries, and unsafe or duplicate paths are not supported.
   */
  function makeZip(entries) {
    if (!Array.isArray(entries)) {
      throw new TypeError("ZIP entries must be an array.");
    }
    if (entries.length > MAX_ZIP_ENTRIES) {
      throw new RangeError("This ZIP exporter supports at most 65,534 files; ZIP64 is not supported.");
    }
    const files = new Set();
    const directories = new Map();
    let localSize = 0;
    let centralSize = 0;
    const prepared = Array.from(entries, (entry) => {
      if (!entry || typeof entry !== "object") {
        throw new TypeError("Each ZIP entry must have a name and file data.");
      }
      const name = registerPath(entry.name, files, directories);
      const bytes = typeof entry.bytes === "string" ? encoder.encode(entry.bytes) : requireBytes(entry.bytes);
      if (bytes.byteLength > MAX_ZIP_VALUE) {
        throw new RangeError("A ZIP file exceeds the supported 32-bit size; ZIP64 is not supported.");
      }
      const offset = localSize;
      localSize += 30 + name.length + bytes.byteLength;
      centralSize += 46 + name.length;
      if (localSize + centralSize + 22 > MAX_ZIP_VALUE) {
        throw new RangeError("The ZIP archive exceeds the supported 32-bit size; ZIP64 is not supported.");
      }
      return { name, bytes, offset };
    });

    let archive;
    try {
      archive = new Uint8Array(localSize + centralSize + 22);
    } catch (error) {
      throw new RangeError("The ZIP archive is too large for this browser's available memory.", { cause: error });
    }
    const view = new DataView(archive.buffer);
    const u16 = (offset, value) => view.setUint16(offset, value, true);
    const u32 = (offset, value) => view.setUint32(offset, value, true);
    let centralOffset = localSize;

    for (const file of prepared) {
      const checksum = crc32(file.bytes);
      const start = file.offset;
      u32(start, 0x04034b50);
      u16(start + 4, 20); // ZIP version 2.0.
      u16(start + 6, 0x0800); // UTF-8 paths; no data descriptor.
      u16(start + 8, 0); // STORE.
      u16(start + 10, 0); // Deterministic DOS time: 1980-01-01 00:00:00.
      u16(start + 12, 0x0021);
      u32(start + 14, checksum);
      u32(start + 18, file.bytes.byteLength);
      u32(start + 22, file.bytes.byteLength);
      u16(start + 26, file.name.length);
      u16(start + 28, 0);
      archive.set(file.name, start + 30);
      archive.set(file.bytes, start + 30 + file.name.length);

      const central = centralOffset;
      u32(central, 0x02014b50);
      u16(central + 4, 20); // DOS creator; ordinary file, no symlinks.
      u16(central + 6, 20);
      u16(central + 8, 0x0800);
      u16(central + 10, 0);
      u16(central + 12, 0);
      u16(central + 14, 0x0021);
      u32(central + 16, checksum);
      u32(central + 20, file.bytes.byteLength);
      u32(central + 24, file.bytes.byteLength);
      u16(central + 28, file.name.length);
      u16(central + 30, 0); // No extra data.
      u16(central + 32, 0); // No comment.
      u16(central + 34, 0); // Single disk.
      u16(central + 36, 0);
      u32(central + 38, 0);
      u32(central + 42, file.offset);
      archive.set(file.name, central + 46);
      centralOffset += 46 + file.name.length;
    }

    u32(centralOffset, 0x06054b50);
    u16(centralOffset + 4, 0);
    u16(centralOffset + 6, 0);
    u16(centralOffset + 8, prepared.length);
    u16(centralOffset + 10, prepared.length);
    u32(centralOffset + 12, centralSize);
    u32(centralOffset + 16, localSize);
    u16(centralOffset + 20, 0);
    return archive;
  }

  /**
   * Read a STORE bundle exported by makeZip, returning independent file-byte copies.
   * Strictly validates structure, names, sizes, and checksums before returning files.
   * Both archive size and total extracted data are limited to 100 MiB.
   */
  function readZip(input) {
    try {
      const archive = requireBytes(input);
      if (archive.byteLength > MAX_IMPORT_BYTES) {
        throw new RangeError("The archive exceeds the 100 MiB import limit.");
      }
      if (archive.byteLength < 22) throw new Error("The archive is truncated or is not a ZIP file.");
      const view = new DataView(archive.buffer, archive.byteOffset, archive.byteLength);
      const u16 = (offset) => view.getUint16(offset, true);
      const u32 = (offset) => view.getUint32(offset, true);
      const end = archive.byteLength - 22;
      if (u32(end) !== 0x06054b50 || u16(end + 20) !== 0) {
        throw new Error("The ZIP end record is missing, truncated, or contains an unsupported comment.");
      }
      const count = u16(end + 10);
      const centralSize = u32(end + 12);
      const centralStart = u32(end + 16);
      if (u16(end + 4) !== 0 || u16(end + 6) !== 0 || u16(end + 8) !== count) {
        throw new Error("Multidisk ZIP archives are not supported.");
      }
      if (count > MAX_ZIP_ENTRIES || centralSize > MAX_ZIP_VALUE || centralStart > MAX_ZIP_VALUE) {
        throw new Error("ZIP64 archives are not supported.");
      }
      if (centralStart + centralSize !== end || centralSize < count * 46) {
        throw new Error("The ZIP central directory has invalid offsets or sizes.");
      }
      const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
      const files = new Set();
      const directories = new Map();
      const prepared = [];
      let cursor = centralStart;
      let nextLocal = 0;
      let totalBytes = 0;
      for (let index = 0; index < count; index += 1) {
        if (cursor + 46 > end || u32(cursor) !== 0x02014b50) {
          throw new Error("The ZIP central directory is truncated or corrupt.");
        }
        const version = u16(cursor + 6);
        const flags = u16(cursor + 8);
        const method = u16(cursor + 10);
        const checksum = u32(cursor + 16);
        const compressedSize = u32(cursor + 20);
        const size = u32(cursor + 24);
        const nameLength = u16(cursor + 28);
        const extraLength = u16(cursor + 30);
        const commentLength = u16(cursor + 32);
        const local = u32(cursor + 42);
        if (flags & 0x0001 || flags & 0x0040) throw new Error("Encrypted ZIP files are not supported.");
        if (method !== 0) throw new Error("Compressed ZIP files are not supported; use the guide's original ZIP export.");
        if (version > 20 || compressedSize > MAX_ZIP_VALUE || size > MAX_ZIP_VALUE || local > MAX_ZIP_VALUE) {
          throw new Error("ZIP64 or newer ZIP features are not supported.");
        }
        if (flags !== 0x0800 || extraLength !== 0 || commentLength !== 0) {
          throw new Error("This archive uses unsupported ZIP flags, extra fields, or file comments.");
        }
        if (u16(cursor + 34) !== 0) throw new Error("Multidisk ZIP archives are not supported.");
        if (compressedSize !== size) throw new Error("A stored ZIP file has inconsistent compressed and uncompressed sizes.");
        totalBytes += size;
        if (totalBytes > MAX_IMPORT_BYTES) throw new RangeError("Extracted files exceed the 100 MiB import limit.");
        if (nameLength === 0 || cursor + 46 + nameLength > end) {
          throw new Error("A ZIP filename is missing or truncated.");
        }
        let name;
        try {
          name = decoder.decode(archive.subarray(cursor + 46, cursor + 46 + nameLength));
        } catch (error) {
          throw new Error("ZIP filenames must contain valid UTF-8.", { cause: error });
        }
        registerPath(name, files, directories);
        if (local !== nextLocal || local + 30 > centralStart || u32(local) !== 0x04034b50) {
          throw new Error("ZIP local files have invalid, overlapping, or out-of-order offsets.");
        }
        if (u16(local + 4) !== version || u16(local + 6) !== flags || u16(local + 8) !== method
          || u16(local + 10) !== u16(cursor + 12) || u16(local + 12) !== u16(cursor + 14)
          || u32(local + 14) !== checksum || u32(local + 18) !== compressedSize || u32(local + 22) !== size
          || u16(local + 26) !== nameLength || u16(local + 28) !== 0) {
          throw new Error("ZIP local and central headers do not match.");
        }
        const dataStart = local + 30 + nameLength;
        const dataEnd = dataStart + size;
        if (dataEnd > centralStart) throw new Error("A ZIP file is truncated or overlaps the central directory.");
        for (let character = 0; character < nameLength; character += 1) {
          if (archive[local + 30 + character] !== archive[cursor + 46 + character]) {
            throw new Error("ZIP local and central filenames do not match.");
          }
        }
        const data = archive.subarray(dataStart, dataEnd);
        if (crc32(data) !== checksum) throw new Error("A ZIP file failed its CRC32 checksum: " + name);
        prepared.push({ name, bytes: data });
        nextLocal = dataEnd;
        cursor += 46 + nameLength;
      }
      if (cursor !== end || nextLocal !== centralStart) {
        throw new Error("The ZIP contains unexpected data or inconsistent file counts.");
      }
      // Copy only after the entire archive has passed validation.
      return prepared.map(({ name, bytes }) => ({ name, bytes: bytes.slice() }));
    } catch (error) {
      throw new Error("Cannot import this ZIP: " + error.message
        + " Only uncompressed ZIP bundles exported by this guide are supported.", { cause: error });
    }
  }

  /** Return a portable lowercase ASCII basename; callers resolve name collisions. */
  function safeAssetName(filename) {
    if (typeof filename !== "string" || !filename.trim() || /[\u0000-\u001f\u007f]/.test(filename)) {
      throw new TypeError("Choose an asset with a valid filename.");
    }
    const basename = filename.replace(/\\/g, "/").split("/").pop();
    const dot = basename.lastIndexOf(".");
    const extension = dot > 0 ? basename.slice(dot + 1).toLowerCase() : "";
    if (!ALLOWED_ASSET_EXTENSIONS.has(extension)) {
      throw new Error("Unsupported asset extension. Use PNG, JPG, JPEG, WebP, GIF, TTF, OTF, TXT, JSON, or PLIST.");
    }
    let stem = basename.slice(0, dot).normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9_-]+/g, "-")
      .replace(/[-_]{2,}/g, "-")
      .replace(/^[-_]+|[-_]+$/g, "")
      .slice(0, 80)
      .replace(/[-_]+$/g, "");
    if (!stem) stem = "asset";
    if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])$/.test(stem)) stem = "asset-" + stem;
    return stem + "." + extension;
  }

  function bytesToBase64(value) {
    const bytes = requireBytes(value);
    const chunks = [];
    let chunk = "";
    for (let index = 0; index < bytes.length; index += 3) {
      const a = bytes[index];
      const b = index + 1 < bytes.length ? bytes[index + 1] : 0;
      const c = index + 2 < bytes.length ? bytes[index + 2] : 0;
      chunk += BASE64[a >>> 2] + BASE64[((a & 3) << 4) | (b >>> 4)]
        + (index + 1 < bytes.length ? BASE64[((b & 15) << 2) | (c >>> 6)] : "=")
        + (index + 2 < bytes.length ? BASE64[c & 63] : "=");
      if (chunk.length >= 0x10000) {
        chunks.push(chunk);
        chunk = "";
      }
    }
    if (chunk) chunks.push(chunk);
    return chunks.join("");
  }

  function base64ToBytes(text) {
    if (typeof text !== "string" || text.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(text)) {
      throw new TypeError("Expected canonical padded Base64 text without whitespace.");
    }
    const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0;
    const last = padding ? BASE64.indexOf(text[text.length - padding - 1]) : 0;
    if ((padding === 2 && (last & 15) !== 0) || (padding === 1 && (last & 3) !== 0)) {
      throw new TypeError("Base64 text contains nonzero padding bits.");
    }
    const bytes = new Uint8Array((text.length / 4) * 3 - padding);
    let destination = 0;
    for (let index = 0; index < text.length; index += 4) {
      const a = BASE64.indexOf(text[index]);
      const b = BASE64.indexOf(text[index + 1]);
      const c = text[index + 2] === "=" ? 0 : BASE64.indexOf(text[index + 2]);
      const d = text[index + 3] === "=" ? 0 : BASE64.indexOf(text[index + 3]);
      bytes[destination++] = (a << 2) | (b >>> 4);
      if (destination < bytes.length) bytes[destination++] = (b << 4) | (c >>> 2);
      if (destination < bytes.length) bytes[destination++] = (c << 6) | d;
    }
    return bytes;
  }

  root.BrandGuideFiles = Object.freeze({ makeZip, readZip, safeAssetName, bytesToBase64, base64ToBytes });
})(globalThis);
