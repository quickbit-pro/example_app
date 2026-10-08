using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddPushNotifications : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "push_devices",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    RegistrationToken = table.Column<string>(type: "character varying(4096)", maxLength: 4096, nullable: false),
                    Platform = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AppVersion = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    Locale = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: true),
                    IsEnabled = table.Column<bool>(type: "boolean", nullable: false),
                    LastSeenAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_push_devices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_push_devices_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_push_devices_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "push_notifications",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    EventId = table.Column<string>(type: "character varying(180)", maxLength: 180, nullable: false),
                    EventType = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Title = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    Body = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    Route = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    DataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    Status = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    NextAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SentAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_push_notifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_push_notifications_company_installations_CompanyInstallatio~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_push_notifications_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_push_devices_CompanyInstallationId",
                schema: "neobanking",
                table: "push_devices",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_push_devices_CompanyInstallationId_UserId_IsEnabled",
                schema: "neobanking",
                table: "push_devices",
                columns: new[] { "CompanyInstallationId", "UserId", "IsEnabled" });

            migrationBuilder.CreateIndex(
                name: "IX_push_devices_RegistrationToken",
                schema: "neobanking",
                table: "push_devices",
                column: "RegistrationToken",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_push_devices_UserId",
                schema: "neobanking",
                table: "push_devices",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_push_notifications_CompanyInstallationId",
                schema: "neobanking",
                table: "push_notifications",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_push_notifications_CompanyInstallationId_UserId_EventId",
                schema: "neobanking",
                table: "push_notifications",
                columns: new[] { "CompanyInstallationId", "UserId", "EventId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_push_notifications_Status_NextAttemptAt",
                schema: "neobanking",
                table: "push_notifications",
                columns: new[] { "Status", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_push_notifications_UserId",
                schema: "neobanking",
                table: "push_notifications",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "push_devices",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "push_notifications",
                schema: "neobanking");
        }
    }
}
