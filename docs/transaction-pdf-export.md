# Transaction PDF export and printing

Tap the printer icon on Activity, card transactions, account history, or a transaction receipt. The export includes the loaded rows and filters shown on that screen.

In the web app or installed PWA, wait for **PDF ready**, then choose:

- **Open PDF**: open the document in a PDF viewer and use its menu to print.
- **Download PDF**: request a named PDF download. If the installed PWA does not save it, use Open PDF or Share PDF.
- **Share PDF** (supported devices): open the system share sheet to send the file to a PDF app or save it to files. Cancelled or failed sharing leaves the prepared PDF available for another action.

These actions run from a fresh tap after generation, preserving the browser user activation needed by Android file sharing and popup opening. Native mobile/desktop apps retain the system save dialog.

The app name comes from the current branding configuration (or the live white-label preview). It appears in the page header, PDF metadata, and sanitized filename. Every statement and receipt page has the footer **Not for official use**.

Exports preserve hidden amounts and masked account/card labels. Generating a PDF does not fetch additional transactions or send the document to a server.
