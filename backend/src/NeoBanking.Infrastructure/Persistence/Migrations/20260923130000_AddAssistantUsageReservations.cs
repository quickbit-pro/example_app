using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAssistantUsageReservations : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "assistant_usage_reservations",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ReservedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ActiveUntil = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_assistant_usage_reservations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_assistant_usage_reservations_company_installations_CompanyI~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_assistant_usage_reservations_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_assistant_usage_reservations_CompanyInstallationId_UserId_A~",
                schema: "neobanking",
                table: "assistant_usage_reservations",
                columns: new[] { "CompanyInstallationId", "UserId", "ActiveUntil" });

            migrationBuilder.CreateIndex(
                name: "IX_assistant_usage_reservations_CompanyInstallationId_UserId_R~",
                schema: "neobanking",
                table: "assistant_usage_reservations",
                columns: new[] { "CompanyInstallationId", "UserId", "ReservedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_assistant_usage_reservations_ReservedAt",
                schema: "neobanking",
                table: "assistant_usage_reservations",
                column: "ReservedAt");

            migrationBuilder.CreateIndex(
                name: "IX_assistant_usage_reservations_UserId",
                schema: "neobanking",
                table: "assistant_usage_reservations",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "assistant_usage_reservations",
                schema: "neobanking");
        }
    }
}
