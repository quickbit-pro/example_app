using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddCustomerSyncSchedule : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ConsecutiveSyncFailures",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "LastSyncAttemptAt",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "NextSyncAt",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "SyncRequestedAt",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_NextSyncAt",
                schema: "neobanking",
                table: "admin_customer_snapshots",
                columns: new[] { "CompanyInstallationId", "NextSyncAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_admin_customer_snapshots_CompanyInstallationId_NextSyncAt",
                schema: "neobanking",
                table: "admin_customer_snapshots");

            migrationBuilder.DropColumn(
                name: "ConsecutiveSyncFailures",
                schema: "neobanking",
                table: "admin_customer_snapshots");

            migrationBuilder.DropColumn(
                name: "LastSyncAttemptAt",
                schema: "neobanking",
                table: "admin_customer_snapshots");

            migrationBuilder.DropColumn(
                name: "NextSyncAt",
                schema: "neobanking",
                table: "admin_customer_snapshots");

            migrationBuilder.DropColumn(
                name: "SyncRequestedAt",
                schema: "neobanking",
                table: "admin_customer_snapshots");
        }
    }
}
