using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddAccountSecurity : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "DuressPasswordHash",
                schema: "neobanking",
                table: "users",
                type: "character varying(512)",
                maxLength: 512,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "LockReason",
                schema: "neobanking",
                table: "users",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "LockedAt",
                schema: "neobanking",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "PasswordChangedAt",
                schema: "neobanking",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RecoveryCodesJson",
                schema: "neobanking",
                table: "users",
                type: "jsonb",
                nullable: false,
                defaultValueSql: "'[]'::jsonb");

            migrationBuilder.AddColumn<bool>(
                name: "TwoFactorEnabled",
                schema: "neobanking",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "TwoFactorEnabledAt",
                schema: "neobanking",
                table: "users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "TwoFactorSecret",
                schema: "neobanking",
                table: "users",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "DuressPasswordHash",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "LockReason",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "LockedAt",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "PasswordChangedAt",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "RecoveryCodesJson",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "TwoFactorEnabled",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "TwoFactorEnabledAt",
                schema: "neobanking",
                table: "users");

            migrationBuilder.DropColumn(
                name: "TwoFactorSecret",
                schema: "neobanking",
                table: "users");
        }
    }
}
