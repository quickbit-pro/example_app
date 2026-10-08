import 'dart:typed_data';

/// Keccak-256 (the pre-standard padding used by Ethereum, not SHA3-256).
///
/// Lanes are kept as pairs of 32-bit halves so the implementation also runs
/// on the web, where Dart ints are JavaScript doubles.
Uint8List keccak256(List<int> input) {
  const rate = 136; // 1088 bits
  final hi = Uint32List(25);
  final lo = Uint32List(25);

  final padded = Uint8List(((input.length ~/ rate) + 1) * rate)
    ..setRange(0, input.length, input);
  padded[input.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;

  for (var offset = 0; offset < padded.length; offset += rate) {
    for (var lane = 0; lane < rate ~/ 8; lane++) {
      final b = offset + lane * 8;
      lo[lane] ^= padded[b] |
          (padded[b + 1] << 8) |
          (padded[b + 2] << 16) |
          (padded[b + 3] << 24);
      hi[lane] ^= padded[b + 4] |
          (padded[b + 5] << 8) |
          (padded[b + 6] << 16) |
          (padded[b + 7] << 24);
    }
    _keccakF(hi, lo);
  }

  final out = Uint8List(32);
  for (var lane = 0; lane < 4; lane++) {
    final l = lo[lane];
    final h = hi[lane];
    out[lane * 8] = l & 0xff;
    out[lane * 8 + 1] = (l >>> 8) & 0xff;
    out[lane * 8 + 2] = (l >>> 16) & 0xff;
    out[lane * 8 + 3] = (l >>> 24) & 0xff;
    out[lane * 8 + 4] = h & 0xff;
    out[lane * 8 + 5] = (h >>> 8) & 0xff;
    out[lane * 8 + 6] = (h >>> 16) & 0xff;
    out[lane * 8 + 7] = (h >>> 24) & 0xff;
  }
  return out;
}

// Round constants split into (hi, lo) 32-bit halves.
const _rcHi = <int>[
  0x00000000,
  0x00000000,
  0x80000000,
  0x80000000,
  0x00000000,
  0x00000000,
  0x80000000,
  0x80000000,
  0x00000000,
  0x00000000,
  0x00000000,
  0x00000000,
  0x00000000,
  0x80000000,
  0x80000000,
  0x80000000,
  0x80000000,
  0x80000000,
  0x00000000,
  0x80000000,
  0x80000000,
  0x80000000,
  0x00000000,
  0x80000000,
];
const _rcLo = <int>[
  0x00000001,
  0x00008082,
  0x0000808A,
  0x80008000,
  0x0000808B,
  0x80000001,
  0x80008081,
  0x00008009,
  0x0000008A,
  0x00000088,
  0x80008009,
  0x8000000A,
  0x8000808B,
  0x0000008B,
  0x00008089,
  0x00008003,
  0x00008002,
  0x00000080,
  0x0000800A,
  0x8000000A,
  0x80008081,
  0x00008080,
  0x80000001,
  0x80008008,
];

// Rotation offsets indexed by lane (x + 5y).
const _rot = <int>[
  0, 1, 62, 28, 27, //
  36, 44, 6, 55, 20, //
  3, 10, 43, 25, 39, //
  41, 45, 15, 21, 8, //
  18, 2, 61, 56, 14, //
];

void _keccakF(Uint32List hi, Uint32List lo) {
  final cHi = Uint32List(5);
  final cLo = Uint32List(5);
  final bHi = Uint32List(25);
  final bLo = Uint32List(25);

  for (var round = 0; round < 24; round++) {
    // θ
    for (var x = 0; x < 5; x++) {
      cHi[x] = hi[x] ^ hi[x + 5] ^ hi[x + 10] ^ hi[x + 15] ^ hi[x + 20];
      cLo[x] = lo[x] ^ lo[x + 5] ^ lo[x + 10] ^ lo[x + 15] ^ lo[x + 20];
    }
    for (var x = 0; x < 5; x++) {
      final nextHi = cHi[(x + 1) % 5];
      final nextLo = cLo[(x + 1) % 5];
      // rot(C[x+1], 1)
      final rHi = ((nextHi << 1) | (nextLo >>> 31)) & 0xFFFFFFFF;
      final rLo = ((nextLo << 1) | (nextHi >>> 31)) & 0xFFFFFFFF;
      final dHi = cHi[(x + 4) % 5] ^ rHi;
      final dLo = cLo[(x + 4) % 5] ^ rLo;
      for (var y = 0; y < 25; y += 5) {
        hi[x + y] ^= dHi;
        lo[x + y] ^= dLo;
      }
    }
    // ρ and π
    for (var x = 0; x < 5; x++) {
      for (var y = 0; y < 5; y++) {
        final from = x + 5 * y;
        final to = y + 5 * ((2 * x + 3 * y) % 5);
        var n = _rot[from];
        var h = hi[from];
        var l = lo[from];
        if (n >= 32) {
          final t = h;
          h = l;
          l = t;
          n -= 32;
        }
        if (n == 0) {
          bHi[to] = h;
          bLo[to] = l;
        } else {
          bHi[to] = ((h << n) | (l >>> (32 - n))) & 0xFFFFFFFF;
          bLo[to] = ((l << n) | (h >>> (32 - n))) & 0xFFFFFFFF;
        }
      }
    }
    // χ
    for (var y = 0; y < 25; y += 5) {
      for (var x = 0; x < 5; x++) {
        hi[x + y] =
            (bHi[x + y] ^ ((~bHi[(x + 1) % 5 + y]) & bHi[(x + 2) % 5 + y])) &
                0xFFFFFFFF;
        lo[x + y] =
            (bLo[x + y] ^ ((~bLo[(x + 1) % 5 + y]) & bLo[(x + 2) % 5 + y])) &
                0xFFFFFFFF;
      }
    }
    // ι
    hi[0] ^= _rcHi[round];
    lo[0] ^= _rcLo[round];
  }
}
