# Private invoice and document storage

Both apps use the Azure Blob account through a server-only `DocumentStorage` configuration section. The connection string belongs in the environment's private settings overlay or secret manager, never in source control, Flutter defines, browser storage, deployment manifests, logs, or a public blob URL.

Each installation must configure its own private document container. The SDK creates them with anonymous access disabled and refuses uploads to a public container. Blob names include company and owner IDs plus SHA-256 of the original bytes. Uploads never overwrite existing bytes. The same content uploaded by the same owner reuses its document ID; different owners remain isolated.

`stored_documents` records the document ID, owner/company, internal blob key, content type, original filename, length, SHA-256, and timestamps. Apply the app's `AddStoredDocuments` migration before enabling uploads. Environment configuration:

```json
{
  "DocumentStorage": {
    "ConnectionString": "<server secret>",
    "Container": "customer-documents"
  }
}
```

Authenticated mobile APIs:

- `POST /api/v1/mobile/documents`, multipart `file`: JPEG, PNG, WebP or PDF up to 10 MiB, identified from bytes. Returns metadata and an opaque document ID.
- `GET /api/v1/mobile/documents`: the owner's latest 100 uploads, including originals saved before an unsuccessful scan.
- `GET /api/v1/mobile/documents/{id}/content`: downloads original bytes through the API after checking company and owner. Uses attachment disposition, no-store and nosniff. No public URLs or SAS tokens are sent to clients.

Both apps support private invoice attachments on transaction details. Use **Take photo** or **Choose file** (JPEG, PNG, WebP or PDF, up to 10 MiB). Images open in a zoomable viewer; PDFs can be opened/downloaded/shared on the web or saved to files on native apps. Multiple invoices can be attached. Removing an attachment keeps the original document available to other references.

Apply `AddTransactionDocuments` before deploying the client. `transaction_documents` links a provider transaction ID to an existing owner-scoped document. These are private user annotations; they never modify or assert the ownership/status of provider ledger entries. The same transaction ID viewed from activity or card details uses the same attachments. API endpoints:

- `GET /api/v1/mobile/transaction-documents?transactionId=...`: current user's attachments for that transaction reference.
- `POST /api/v1/mobile/transaction-documents` with `transactionId` and `documentId`: validates document ownership and creates an idempotent attachment.
- `DELETE /api/v1/mobile/transaction-documents/{attachmentId}`: removes only the current user's attachment.

Tests cover original-byte preservation, repeat uploads, owner/company isolation, unsupported content, storage failures and retained bill references. Azure verification is opt-in using `DOCUMENT_STORAGE_SMOKE_SETTINGS` pointing to a private JSON file with the configuration above. It creates and deletes a uniquely named synthetic image, verifies identical downloaded bytes, and confirms anonymous reads fail. Normal test runs do not access Azure.

The invoice panel keeps failed uploads visible and retries attachment using the already stored document ID. Web file inputs remain attached until an explicit selection or cancellation event; returning window focus is not treated as cancellation. HTTP regression tests cover multipart upload, MVC record validation, idempotent attachment and listing.

## Monthly statements

Transactions includes a **Monthly statement with invoices** action in Example and Hoppa. It queues a durable export for a calendar month in UTC. The ZIP contains a PDF and UTF-8 CSV plus private invoice copies named `invoices/0001_Merchant_01.ext`; those exact paths are listed on the matching statement row. Original document records and filenames are unchanged. Card-detail references are matched to the unified transaction's external reference; ambiguous matches fail rather than placing an invoice on the wrong row.

`POST /api/v1/mobile/monthly-statements` accepts a client-generated request ID, year and month; the provider user comes from authenticated claims. GET list/detail returns queued/processing/ready/failed status and an expiring download path when ready. A background worker fetches every provider page and refuses a partial/changing month, verifies every invoice read, then saves the ZIP in the existing private document container. Download paths expire after 15 minutes; refresh the export list to mint another. Downloads recheck the export owner and account lock state. No bank balance or cross-currency total is inferred.

The `AddMonthlyStatementExports` migration adds the job table and one-active-export-per-owner index. Jobs continue after leaving the page and recover interrupted workers after a 10-minute lease; each attempt is limited to six minutes, with at most three interrupted attempts. Limits: 12 exports per owner per day, 20,000 transactions and 200 MB of attached originals per ZIP. Failed exports never expose a partial archive. The PDF renderer uses MIT-licensed PDFsharp and the existing OFL-licensed Geist font; the CSV preserves full Unicode transaction text. No new storage secret or public container is required.
