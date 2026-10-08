using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddMonthlyStatementExports : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "monthly_statement_exports",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProviderUserId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Year = table.Column<int>(type: "integer", nullable: false),
                    Month = table.Column<int>(type: "integer", nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    Attempt = table.Column<int>(type: "integer", nullable: false),
                    TransactionCount = table.Column<int>(type: "integer", nullable: false),
                    AttachmentCount = table.Column<int>(type: "integer", nullable: false),
                    ByteLength = table.Column<long>(type: "bigint", nullable: false),
                    BlobKey = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    ErrorMessage = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_monthly_statement_exports", x => x.Id);
                    table.ForeignKey(
                        name: "FK_monthly_statement_exports_company_installations_CompanyInst~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_monthly_statement_exports_users_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_monthly_statement_exports_CompanyInstallationId",
                schema: "neobanking",
                table: "monthly_statement_exports",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_monthly_statement_exports_CompanyInstallationId_OwnerUserId",
                schema: "neobanking",
                table: "monthly_statement_exports",
                columns: new[] { "CompanyInstallationId", "OwnerUserId" },
                unique: true,
                filter: "\"Status\" IN ('queued', 'processing')");

            migrationBuilder.CreateIndex(
                name: "IX_monthly_statement_exports_CompanyInstallationId_OwnerUserId~",
                schema: "neobanking",
                table: "monthly_statement_exports",
                columns: new[] { "CompanyInstallationId", "OwnerUserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_monthly_statement_exports_OwnerUserId",
                schema: "neobanking",
                table: "monthly_statement_exports",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_monthly_statement_exports_Status_UpdatedAt",
                schema: "neobanking",
                table: "monthly_statement_exports",
                columns: new[] { "Status", "UpdatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "monthly_statement_exports",
                schema: "neobanking");
        }
    }
}
