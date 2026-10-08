using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace NeoBanking.Infrastructure.Persistence.Migrations;

[DbContext(typeof(NeoBankingDbContext))]
[Migration("20260923120000_AddActivationProgress")]
public sealed class AddActivationProgress : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<DateTimeOffset>(name: "ActivationIntroShownAt", schema: "neobanking", table: "users", type: "timestamp with time zone", nullable: true);
        migrationBuilder.AddColumn<DateTimeOffset>(name: "FirstDepositObservedAt", schema: "neobanking", table: "users", type: "timestamp with time zone", nullable: true);
    }
    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(name: "ActivationIntroShownAt", schema: "neobanking", table: "users");
        migrationBuilder.DropColumn(name: "FirstDepositObservedAt", schema: "neobanking", table: "users");
    }
}
