using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddMarketRateSnapshots : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "market_rate_snapshots",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    BaseCurrency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    QuoteCurrency = table.Column<string>(type: "character varying(12)", maxLength: 12, nullable: false),
                    Rate = table.Column<decimal>(type: "numeric(28,12)", precision: 28, scale: 12, nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ObservedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_market_rate_snapshots", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_market_rate_snapshots_BaseCurrency_QuoteCurrency_ObservedAt",
                schema: "neobanking",
                table: "market_rate_snapshots",
                columns: new[] { "BaseCurrency", "QuoteCurrency", "ObservedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_market_rate_snapshots_BaseCurrency_QuoteCurrency_Provider_O~",
                schema: "neobanking",
                table: "market_rate_snapshots",
                columns: new[] { "BaseCurrency", "QuoteCurrency", "Provider", "ObservedAt" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "market_rate_snapshots",
                schema: "neobanking");
        }
    }
}
