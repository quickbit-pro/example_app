using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTransactionDocuments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "transaction_documents",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    TransactionId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    DocumentId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_transaction_documents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_transaction_documents_company_installations_CompanyInstalla~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_transaction_documents_stored_documents_DocumentId",
                        column: x => x.DocumentId,
                        principalSchema: "neobanking",
                        principalTable: "stored_documents",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_transaction_documents_users_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_transaction_documents_CompanyInstallationId",
                schema: "neobanking",
                table: "transaction_documents",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_transaction_documents_CompanyInstallationId_OwnerUserId_Tra~",
                schema: "neobanking",
                table: "transaction_documents",
                columns: new[] { "CompanyInstallationId", "OwnerUserId", "TransactionId", "DocumentId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_transaction_documents_DocumentId",
                schema: "neobanking",
                table: "transaction_documents",
                column: "DocumentId");

            migrationBuilder.CreateIndex(
                name: "IX_transaction_documents_OwnerUserId",
                schema: "neobanking",
                table: "transaction_documents",
                column: "OwnerUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "transaction_documents",
                schema: "neobanking");
        }
    }
}
