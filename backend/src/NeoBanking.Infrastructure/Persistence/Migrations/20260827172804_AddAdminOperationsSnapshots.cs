using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAdminOperationsSnapshots : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "admin_customer_snapshots",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProviderUserId = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    CustomerType = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    OnboardingStatus = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    OnboardingStep = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    OnboardingStartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    OnboardingCompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    OnboardingUpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    VerificationStatus = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    VerificationLevel = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    VerificationSubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    VerificationReviewedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    BalanceSummaryJson = table.Column<string>(type: "jsonb", nullable: false),
                    AccountSummaryJson = table.Column<string>(type: "jsonb", nullable: false),
                    CardSummaryJson = table.Column<string>(type: "jsonb", nullable: false),
                    RecentTransactionsJson = table.Column<string>(type: "jsonb", nullable: false),
                    VerificationDetailsJson = table.Column<string>(type: "jsonb", nullable: false),
                    AccountCount = table.Column<int>(type: "integer", nullable: false),
                    ActiveCardCount = table.Column<int>(type: "integer", nullable: false),
                    TotalCardCount = table.Column<int>(type: "integer", nullable: false),
                    CompletedTransactionCount30d = table.Column<int>(type: "integer", nullable: false),
                    TransactionInflow30dJson = table.Column<string>(type: "jsonb", nullable: false),
                    TransactionOutflow30dJson = table.Column<string>(type: "jsonb", nullable: false),
                    LastTransactionAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LastActivityAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LastSyncedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LastSyncError = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_admin_customer_snapshots", x => x.Id);
                    table.ForeignKey(
                        name: "FK_admin_customer_snapshots_company_installations_CompanyInsta~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_admin_customer_snapshots_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "admin_daily_financial_summaries",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Day = table.Column<DateOnly>(type: "date", nullable: false),
                    Currency = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    CompletedTransactionCount = table.Column<int>(type: "integer", nullable: false),
                    InflowMinor = table.Column<long>(type: "bigint", nullable: false),
                    OutflowMinor = table.Column<long>(type: "bigint", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_admin_daily_financial_summaries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_admin_daily_financial_summaries_company_installations_Compa~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_admin_daily_financial_summaries_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_LastActivity~",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                columns: new[] { "CompanyInstallationId", "LastActivityAt" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_LastSyncedAt",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                columns: new[] { "CompanyInstallationId", "LastSyncedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_UserId",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                columns: new[] { "CompanyInstallationId", "UserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_Verification~",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                columns: new[] { "CompanyInstallationId", "VerificationStatus" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_UserId",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_daily_financial_summaries_CompanyInstallationId",
                schema: "neobanking",
                table: "admin_daily_financial_summaries",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_daily_financial_summaries_CompanyInstallationId_Day_C~",
                schema: "neobanking",
                table: "admin_daily_financial_summaries",
                columns: new[] { "CompanyInstallationId", "Day", "Currency" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_daily_financial_summaries_CompanyInstallationId_UserI~",
                schema: "neobanking",
                table: "admin_daily_financial_summaries",
                columns: new[] { "CompanyInstallationId", "UserId", "Day", "Currency" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_admin_daily_financial_summaries_UserId",
                schema: "neobanking",
                table: "admin_daily_financial_summaries",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "admin_customer_snapshots",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "admin_daily_financial_summaries",
                schema: "neobanking");
        }
    }
}
