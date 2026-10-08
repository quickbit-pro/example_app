using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddStoredDocuments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "stored_documents",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    BlobKey = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    FileName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    ContentType = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Sha256 = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ByteLength = table.Column<long>(type: "bigint", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_stored_documents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_stored_documents_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_stored_documents_users_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_stored_documents_CompanyInstallationId",
                schema: "neobanking",
                table: "stored_documents",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_stored_documents_CompanyInstallationId_OwnerUserId_Sha256",
                schema: "neobanking",
                table: "stored_documents",
                columns: new[] { "CompanyInstallationId", "OwnerUserId", "Sha256" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_stored_documents_OwnerUserId",
                schema: "neobanking",
                table: "stored_documents",
                column: "OwnerUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "stored_documents",
                schema: "neobanking");
        }
    }
}
