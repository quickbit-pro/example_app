using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminTransactionLedger : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "admin_customer_flags",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    IsTestAccount = table.Column<bool>(type: "boolean", nullable: false),
                    UpdatedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_admin_customer_flags", x => x.Id);
                    table.ForeignKey(
                        name: "FK_admin_customer_flags_company_installations_CompanyInstallat~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_admin_customer_flags_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "admin_transactions",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProviderTransactionId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    OccurredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RawType = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    RawStatus = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Status = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    Kind = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    FeeType = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: true),
                    Direction = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(28,8)", precision: 28, scale: 8, nullable: false),
                    Currency = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: false),
                    Description = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    Merchant = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    MerchantCategory = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    CardReference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    WalletReference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    BudgetReference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    AccountReference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    ExternalReference = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    RelatedReference = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    ClientReference = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    FeeAmount = table.Column<decimal>(type: "numeric(28,8)", precision: 28, scale: 8, nullable: true),
                    FeeCurrency = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: true),
                    IsPrimary = table.Column<bool>(type: "boolean", nullable: false),
                    IsDuplicate = table.Column<bool>(type: "boolean", nullable: false),
                    LastSeenAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_admin_transactions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_admin_transactions_company_installations_CompanyInstallatio~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_admin_transactions_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_flags_CompanyInstallationId",
                schema: "neobanking",
                table: "admin_customer_flags",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_flags_CompanyInstallationId_UserId",
                schema: "neobanking",
                table: "admin_customer_flags",
                columns: new[] { "CompanyInstallationId", "UserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_flags_UserId",
                schema: "neobanking",
                table: "admin_customer_flags",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_CompanyInstallationId",
                schema: "neobanking",
                table: "admin_transactions",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_CompanyInstallationId_Kind_OccurredAt",
                schema: "neobanking",
                table: "admin_transactions",
                columns: new[] { "CompanyInstallationId", "Kind", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_CompanyInstallationId_OccurredAt",
                schema: "neobanking",
                table: "admin_transactions",
                columns: new[] { "CompanyInstallationId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_CompanyInstallationId_ProviderTransactio~",
                schema: "neobanking",
                table: "admin_transactions",
                columns: new[] { "CompanyInstallationId", "ProviderTransactionId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_CompanyInstallationId_UserId_OccurredAt",
                schema: "neobanking",
                table: "admin_transactions",
                columns: new[] { "CompanyInstallationId", "UserId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_transactions_UserId",
                schema: "neobanking",
                table: "admin_transactions",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "admin_customer_flags",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "admin_transactions",
                schema: "neobanking");
        }
    }
}
