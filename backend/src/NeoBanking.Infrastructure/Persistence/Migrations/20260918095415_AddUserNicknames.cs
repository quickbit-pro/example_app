using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddUserNicknames : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Nickname",
                schema: "neobanking",
                table: "users",
                type: "character varying(30)",
                maxLength: 30,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_users_company_nickname",
                schema: "neobanking",
                table: "users",
                columns: new[] { "CompanyInstallationId", "Nickname" },
                unique: true);

            migrationBuilder.AddCheckConstraint(
                name: "CK_users_nickname_format",
                schema: "neobanking",
                table: "users",
                sql: "\"Nickname\" IS NULL OR \"Nickname\" ~ '^[a-z][a-z0-9_]{2,29}$'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_users_company_nickname",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropCheckConstraint(
                name: "CK_users_nickname_format",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "Nickname",
                schema: "neobanking",
                table: "users");
        }
    }
}
