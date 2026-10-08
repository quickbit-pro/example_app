using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class DropDatabaseUuidDefaults : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(
                """
                DO $$
                DECLARE
                    table_name text;
                BEGIN
                    FOREACH table_name IN ARRAY ARRAY[
                        'admin_profiles',
                        'audit_log_entries',
                        'banking_snapshots',
                        'cards',
                        'company_installations',
                        'idempotency_records',
                        'kyb_verifications',
                        'kyc_verifications',
                        'onboarding_applications',
                        'provider_mappings',
                        'refresh_sessions',
                        'user_identities',
                        'users',
                        'webhook_deliveries',
                        'webhook_endpoints'
                    ]
                    LOOP
                        EXECUTE format('ALTER TABLE neobanking.%I ALTER COLUMN "Id" DROP DEFAULT', table_name);
                    END LOOP;
                END $$;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Intentionally no-op: database-generated UUID defaults were legacy schema drift,
            // not part of the EF model this migration rolls back to.
        }
    }
}
