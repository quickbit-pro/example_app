using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddDurableReferralSignup : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "referral_signup_attempts",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    EmailNormalized = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: true),
                    LocalUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    State = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    ProviderUserId = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    QuoteId = table.Column<Guid>(type: "uuid", nullable: true),
                    ReferralCode = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    Source = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    QuoteJson = table.Column<string>(type: "jsonb", nullable: false),
                    ConsentReceivedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    FailureReason = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_referral_signup_attempts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_referral_signup_attempts_company_installations_CompanyInsta~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "referral_attribution_intents",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Kind = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    SignupAttemptId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ProviderUserId = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    State = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    PayloadJson = table.Column<string>(type: "jsonb", nullable: false),
                    ResultJson = table.Column<string>(type: "jsonb", nullable: true),
                    Reason = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    Attempts = table.Column<int>(type: "integer", nullable: false),
                    DueAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LeaseToken = table.Column<Guid>(type: "uuid", nullable: true),
                    LeaseUntil = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_referral_attribution_intents", x => x.Id);
                    table.ForeignKey(
                        name: "FK_referral_attribution_intents_company_installations_CompanyI~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_referral_attribution_intents_referral_signup_attempts_Signu~",
                        column: x => x.SignupAttemptId,
                        principalSchema: "neobanking",
                        principalTable: "referral_signup_attempts",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_referral_attribution_intents_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_referral_attribution_intents_CompanyInstallationId",
                schema: "neobanking",
                table: "referral_attribution_intents",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_referral_attribution_intents_CompanyInstallationId_UserId",
                schema: "neobanking",
                table: "referral_attribution_intents",
                columns: new[] { "CompanyInstallationId", "UserId" });

            migrationBuilder.CreateIndex(
                name: "IX_referral_attribution_intents_SignupAttemptId_Kind",
                schema: "neobanking",
                table: "referral_attribution_intents",
                columns: new[] { "SignupAttemptId", "Kind" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_referral_attribution_intents_State_DueAt_LeaseUntil",
                schema: "neobanking",
                table: "referral_attribution_intents",
                columns: new[] { "State", "DueAt", "LeaseUntil" });

            migrationBuilder.CreateIndex(
                name: "IX_referral_attribution_intents_UserId",
                schema: "neobanking",
                table: "referral_attribution_intents",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_referral_signup_attempts_CompanyInstallationId",
                schema: "neobanking",
                table: "referral_signup_attempts",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_referral_signup_attempts_CompanyInstallationId_EmailNormali~",
                schema: "neobanking",
                table: "referral_signup_attempts",
                columns: new[] { "CompanyInstallationId", "EmailNormalized" },
                unique: true,
                filter: "\"EmailNormalized\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_referral_signup_attempts_CompanyInstallationId_LocalUserId",
                schema: "neobanking",
                table: "referral_signup_attempts",
                columns: new[] { "CompanyInstallationId", "LocalUserId" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "referral_attribution_intents",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "referral_signup_attempts",
                schema: "neobanking");
        }
    }
}
