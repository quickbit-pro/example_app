using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddNotificationReadState : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ReadAt",
                schema: "neobanking",
                table: "push_notifications",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_push_notifications_CompanyInstallationId_UserId_ReadAt_Crea~",
                schema: "neobanking",
                table: "push_notifications",
                columns: new[] { "CompanyInstallationId", "UserId", "ReadAt", "CreatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_push_notifications_CompanyInstallationId_UserId_ReadAt_Crea~",
                schema: "neobanking",
                table: "push_notifications");

            migrationBuilder.DropColumn(
                name: "ReadAt",
                schema: "neobanking",
                table: "push_notifications");
        }
    }
}
