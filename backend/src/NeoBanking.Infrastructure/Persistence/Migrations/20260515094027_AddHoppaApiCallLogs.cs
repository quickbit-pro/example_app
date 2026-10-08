using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddHoppaApiCallLogs : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "hoppa_api_call_logs",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActorUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    TraceId = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    IpAddress = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    UserAgent = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    OccurredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    AppMethod = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    AppPath = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    AppQueryString = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    AppStatusCode = table.Column<int>(type: "integer", nullable: true),
                    AppRequestJson = table.Column<string>(type: "jsonb", nullable: true),
                    AppResponseJson = table.Column<string>(type: "jsonb", nullable: true),
                    HoppaMethod = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    HoppaEndpoint = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    HoppaQueryString = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    HoppaStatusCode = table.Column<int>(type: "integer", nullable: true),
                    HoppaDurationMs = table.Column<long>(type: "bigint", nullable: false),
                    Succeeded = table.Column<bool>(type: "boolean", nullable: false),
                    FailureCode = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    FailureMessage = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    HoppaRequestJson = table.Column<string>(type: "jsonb", nullable: true),
                    HoppaResponseJson = table.Column<string>(type: "jsonb", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_hoppa_api_call_logs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_hoppa_api_call_logs_company_installations_CompanyInstallati~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_hoppa_api_call_logs_users_ActorUserId",
                        column: x => x.ActorUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_ActorUserId_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                columns: new[] { "ActorUserId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_CompanyInstallationId_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                columns: new[] { "CompanyInstallationId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_HoppaEndpoint_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                columns: new[] { "HoppaEndpoint", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_Succeeded_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                columns: new[] { "Succeeded", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_TraceId",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                column: "TraceId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "hoppa_api_call_logs",
                schema: "neobanking");
        }
    }
}
