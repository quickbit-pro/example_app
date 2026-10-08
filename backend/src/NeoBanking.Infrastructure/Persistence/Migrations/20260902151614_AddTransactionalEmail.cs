using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTransactionalEmail : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "EmailVerifiedAt",
                schema: "neobanking",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            // Accounts created before email confirmation existed are treated as
            // verified so enabling Email:RequireVerifiedEmailForLogin never locks
            // out existing customers.
            migrationBuilder.Sql(
                "UPDATE neobanking.users SET \"EmailVerifiedAt\" = \"CreatedAt\" WHERE \"EmailVerifiedAt\" IS NULL;");

            migrationBuilder.CreateTable(
                name: "email_messages",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    TemplateKey = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ToEmail = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    ToName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    Subject = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: false),
                    HtmlBody = table.Column<string>(type: "text", nullable: false),
                    TextBody = table.Column<string>(type: "text", nullable: false),
                    Status = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    NextAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SentAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ProviderMessageId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_email_messages", x => x.Id);
                    table.ForeignKey(
                        name: "FK_email_messages_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_email_messages_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "email_templates",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Key = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Subject = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    HtmlBody = table.Column<string>(type: "text", nullable: false),
                    TextBody = table.Column<string>(type: "text", nullable: false),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    UpdatedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_email_templates", x => x.Id);
                    table.ForeignKey(
                        name: "FK_email_templates_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_verification_codes",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Purpose = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    CodeHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ConsumedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    MaxAttempts = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_verification_codes", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_verification_codes_company_installations_CompanyInstal~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_user_verification_codes_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_email_messages_CompanyInstallationId",
                schema: "neobanking",
                table: "email_messages",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_email_messages_CompanyInstallationId_CreatedAt",
                schema: "neobanking",
                table: "email_messages",
                columns: new[] { "CompanyInstallationId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_email_messages_Status_NextAttemptAt",
                schema: "neobanking",
                table: "email_messages",
                columns: new[] { "Status", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_email_messages_UserId",
                schema: "neobanking",
                table: "email_messages",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_email_templates_CompanyInstallationId",
                schema: "neobanking",
                table: "email_templates",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_email_templates_CompanyInstallationId_Key",
                schema: "neobanking",
                table: "email_templates",
                columns: new[] { "CompanyInstallationId", "Key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_verification_codes_CompanyInstallationId",
                schema: "neobanking",
                table: "user_verification_codes",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_user_verification_codes_UserId_Purpose_ConsumedAt_ExpiresAt",
                schema: "neobanking",
                table: "user_verification_codes",
                columns: new[] { "UserId", "Purpose", "ConsumedAt", "ExpiresAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "email_messages",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "email_templates",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "user_verification_codes",
                schema: "neobanking");

            migrationBuilder.DropColumn(
                name: "EmailVerifiedAt",
                schema: "neobanking",
                table: "users");
        }
    }
}
