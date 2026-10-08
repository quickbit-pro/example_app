using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddHoppaApiLogDirection : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Direction",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "outbound");

            migrationBuilder.CreateIndex(
                name: "IX_hoppa_api_call_logs_Direction_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs",
                columns: new[] { "Direction", "OccurredAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_hoppa_api_call_logs_Direction_OccurredAt",
                schema: "neobanking",
                table: "hoppa_api_call_logs");

            migrationBuilder.DropColumn(
                name: "Direction",
                schema: "neobanking",
                table: "hoppa_api_call_logs");
        }
    }
}
