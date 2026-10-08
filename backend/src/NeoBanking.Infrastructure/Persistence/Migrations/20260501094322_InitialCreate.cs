using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.EnsureSchema(
                name: "neobanking");
            migrationBuilder.CreateTable(
                name: "company_installations",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Slug = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    LegalName = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    DisplayName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    CountryCode = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    DefaultCurrency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    SettingsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_company_installations", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "idempotency_records",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Scope = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    Key = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    RequestHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    ResponseStatusCode = table.Column<int>(type: "integer", nullable: true),
                    LockedUntil = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ResponseBodyJson = table.Column<string>(type: "jsonb", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_idempotency_records", x => x.Id);
                    table.ForeignKey(
                        name: "FK_idempotency_records_company_installations_CompanyInstallati~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "provider_mappings",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderEntityType = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderEntityId = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    InternalEntityType = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    InternalEntityId = table.Column<Guid>(type: "uuid", nullable: false),
                    ExternalStatus = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    LastSyncedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SyncStateJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_provider_mappings", x => x.Id);
                    table.ForeignKey(
                        name: "FK_provider_mappings_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "users",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Email = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    EmailNormalized = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: false),
                    PhoneNumber = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: true),
                    DisplayName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Locale = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    TimeZone = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    LastLoginAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RiskProfileJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_users", x => x.Id);
                    table.ForeignKey(
                        name: "FK_users_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "webhook_endpoints",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Url = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: false),
                    Description = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    SecretHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    EventTypesJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    HeadersJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_webhook_endpoints", x => x.Id);
                    table.ForeignKey(
                        name: "FK_webhook_endpoints_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "admin_profiles",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Role = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    PermissionsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    IsBreakGlass = table.Column<bool>(type: "boolean", nullable: false),
                    ApprovedByUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ApprovedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_admin_profiles", x => x.Id);
                    table.ForeignKey(
                        name: "FK_admin_profiles_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_admin_profiles_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "audit_log_entries",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActorUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    ActorIdentityId = table.Column<Guid>(type: "uuid", nullable: true),
                    Action = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    EntityType = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    EntityId = table.Column<Guid>(type: "uuid", nullable: true),
                    TraceId = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    IpAddress = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    UserAgent = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    OccurredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    BeforeJson = table.Column<string>(type: "jsonb", nullable: true),
                    AfterJson = table.Column<string>(type: "jsonb", nullable: true),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_audit_log_entries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_audit_log_entries_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_audit_log_entries_users_ActorUserId",
                        column: x => x.ActorUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "banking_snapshots",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderReference = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    SnapshotType = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    AsOf = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    AvailableBalanceMinor = table.Column<long>(type: "bigint", nullable: true),
                    CurrentBalanceMinor = table.Column<long>(type: "bigint", nullable: true),
                    SourceHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    SnapshotJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_banking_snapshots", x => x.Id);
                    table.ForeignKey(
                        name: "FK_banking_snapshots_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_banking_snapshots_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "cards",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderCardId = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    CardType = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    LastFour = table.Column<string>(type: "character varying(4)", maxLength: 4, nullable: false),
                    Bin = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: true),
                    ExpiryMonth = table.Column<int>(type: "integer", nullable: true),
                    ExpiryYear = table.Column<int>(type: "integer", nullable: true),
                    Currency = table.Column<string>(type: "character varying(3)", maxLength: 3, nullable: false),
                    IssuedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ActivatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SuspendedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ClosedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    SpendingControlsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    BillingAddressJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_cards", x => x.Id);
                    table.ForeignKey(
                        name: "FK_cards_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_cards_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "onboarding_applications",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ApplicantUserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Kind = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    WorkflowVersion = table.Column<int>(type: "integer", nullable: false),
                    CurrentStep = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    SubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    FormDataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    DecisionJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_onboarding_applications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_onboarding_applications_company_installations_CompanyInstal~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_onboarding_applications_users_ApplicantUserId",
                        column: x => x.ApplicantUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "refresh_sessions",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: false),
                    RotatedFromTokenHash = table.Column<string>(type: "character varying(128)", maxLength: 128, nullable: true),
                    DeviceId = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    DeviceName = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: true),
                    IpAddress = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    UserAgent = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LastUsedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RevokedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RevocationReason = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    MetadataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_refresh_sessions", x => x.Id);
                    table.ForeignKey(
                        name: "FK_refresh_sessions_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_refresh_sessions_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "user_identities",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    Subject = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    EmailAtProvider = table.Column<string>(type: "character varying(320)", maxLength: 320, nullable: true),
                    PasswordHash = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    IsPrimary = table.Column<bool>(type: "boolean", nullable: false),
                    LastAuthenticatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ClaimsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_identities", x => x.Id);
                    table.ForeignKey(
                        name: "FK_user_identities_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_user_identities_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "webhook_deliveries",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    WebhookEndpointId = table.Column<Guid>(type: "uuid", nullable: true),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    EventId = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    EventType = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    AttemptCount = table.Column<int>(type: "integer", nullable: false),
                    ReceivedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LastAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    NextAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ProcessedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ResponseStatusCode = table.Column<int>(type: "integer", nullable: true),
                    ResponseBody = table.Column<string>(type: "character varying(4096)", maxLength: 4096, nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(2048)", maxLength: 2048, nullable: true),
                    IdempotencyKey = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    HeadersJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    PayloadJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_webhook_deliveries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_webhook_deliveries_company_installations_CompanyInstallatio~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_webhook_deliveries_webhook_endpoints_WebhookEndpointId",
                        column: x => x.WebhookEndpointId,
                        principalSchema: "neobanking",
                        principalTable: "webhook_endpoints",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "kyb_verifications",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OnboardingApplicationId = table.Column<Guid>(type: "uuid", nullable: true),
                    BusinessName = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: false),
                    RegistrationNumber = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: true),
                    CountryCode = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderReference = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    SubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReviewedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    BusinessProfileJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    BeneficialOwnersJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'[]'::jsonb"),
                    DocumentChecksJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    RiskSignalsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_kyb_verifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_kyb_verifications_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_kyb_verifications_onboarding_applications_OnboardingApplica~",
                        column: x => x.OnboardingApplicationId,
                        principalSchema: "neobanking",
                        principalTable: "onboarding_applications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "kyc_verifications",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    OnboardingApplicationId = table.Column<Guid>(type: "uuid", nullable: true),
                    Provider = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    ProviderReference = table.Column<string>(type: "character varying(240)", maxLength: 240, nullable: true),
                    Status = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Level = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    CountryCode = table.Column<string>(type: "character varying(2)", maxLength: 2, nullable: false),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    SubmittedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ReviewedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    ApplicantDataJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    DocumentChecksJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    RiskSignalsJson = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_kyc_verifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_kyc_verifications_company_installations_CompanyInstallation~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_kyc_verifications_onboarding_applications_OnboardingApplica~",
                        column: x => x.OnboardingApplicationId,
                        principalSchema: "neobanking",
                        principalTable: "onboarding_applications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_kyc_verifications_users_UserId",
                        column: x => x.UserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_admin_profiles_CompanyInstallationId",
                schema: "neobanking",
                table: "admin_profiles",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_admin_profiles_CompanyInstallationId_Role",
                schema: "neobanking",
                table: "admin_profiles",
                columns: new[] { "CompanyInstallationId", "Role" });

            migrationBuilder.CreateIndex(
                name: "IX_admin_profiles_UserId",
                schema: "neobanking",
                table: "admin_profiles",
                column: "UserId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_entries_ActorUserId_OccurredAt",
                schema: "neobanking",
                table: "audit_log_entries",
                columns: new[] { "ActorUserId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_entries_CompanyInstallationId_OccurredAt",
                schema: "neobanking",
                table: "audit_log_entries",
                columns: new[] { "CompanyInstallationId", "OccurredAt" });

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_entries_EntityType_EntityId",
                schema: "neobanking",
                table: "audit_log_entries",
                columns: new[] { "EntityType", "EntityId" });

            migrationBuilder.CreateIndex(
                name: "IX_audit_log_entries_TraceId",
                schema: "neobanking",
                table: "audit_log_entries",
                column: "TraceId");

            migrationBuilder.CreateIndex(
                name: "IX_banking_snapshots_CompanyInstallationId",
                schema: "neobanking",
                table: "banking_snapshots",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_banking_snapshots_CompanyInstallationId_Provider_ProviderRe~",
                schema: "neobanking",
                table: "banking_snapshots",
                columns: new[] { "CompanyInstallationId", "Provider", "ProviderReference", "SnapshotType", "AsOf" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_banking_snapshots_CompanyInstallationId_UserId_AsOf",
                schema: "neobanking",
                table: "banking_snapshots",
                columns: new[] { "CompanyInstallationId", "UserId", "AsOf" });

            migrationBuilder.CreateIndex(
                name: "IX_banking_snapshots_SourceHash",
                schema: "neobanking",
                table: "banking_snapshots",
                column: "SourceHash");

            migrationBuilder.CreateIndex(
                name: "IX_banking_snapshots_UserId",
                schema: "neobanking",
                table: "banking_snapshots",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_cards_CompanyInstallationId",
                schema: "neobanking",
                table: "cards",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_cards_CompanyInstallationId_LastFour",
                schema: "neobanking",
                table: "cards",
                columns: new[] { "CompanyInstallationId", "LastFour" });

            migrationBuilder.CreateIndex(
                name: "IX_cards_CompanyInstallationId_Provider_ProviderCardId",
                schema: "neobanking",
                table: "cards",
                columns: new[] { "CompanyInstallationId", "Provider", "ProviderCardId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_cards_CompanyInstallationId_UserId_Status",
                schema: "neobanking",
                table: "cards",
                columns: new[] { "CompanyInstallationId", "UserId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_cards_UserId",
                schema: "neobanking",
                table: "cards",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_company_installations_Slug",
                schema: "neobanking",
                table: "company_installations",
                column: "Slug",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_company_installations_Status",
                schema: "neobanking",
                table: "company_installations",
                column: "Status");

            migrationBuilder.Sql("""
                INSERT INTO neobanking.company_installations
                    ("Id", "Slug", "LegalName", "DisplayName", "Status", "CountryCode", "DefaultCurrency", "SettingsJson", "CreatedAt", "UpdatedAt")
                VALUES
                    ('019de30e-f84b-7fb1-8cef-4ddc4aba335f', 'default', 'NeoBanking Default Company', 'Default', 'active', 'US', 'USD',
                     '{"seeded":true,"source":"20260501094322_InitialCreate"}'::jsonb, now(), now())
                ON CONFLICT ("Slug") DO NOTHING;
                """);

            migrationBuilder.CreateIndex(
                name: "IX_idempotency_records_CompanyInstallationId",
                schema: "neobanking",
                table: "idempotency_records",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_idempotency_records_CompanyInstallationId_Scope_Key",
                schema: "neobanking",
                table: "idempotency_records",
                columns: new[] { "CompanyInstallationId", "Scope", "Key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_idempotency_records_CompanyInstallationId_Status_LockedUntil",
                schema: "neobanking",
                table: "idempotency_records",
                columns: new[] { "CompanyInstallationId", "Status", "LockedUntil" });

            migrationBuilder.CreateIndex(
                name: "IX_idempotency_records_ExpiresAt",
                schema: "neobanking",
                table: "idempotency_records",
                column: "ExpiresAt");

            migrationBuilder.CreateIndex(
                name: "IX_kyb_verifications_CompanyInstallationId",
                schema: "neobanking",
                table: "kyb_verifications",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_kyb_verifications_CompanyInstallationId_Provider_ProviderRe~",
                schema: "neobanking",
                table: "kyb_verifications",
                columns: new[] { "CompanyInstallationId", "Provider", "ProviderReference" });

            migrationBuilder.CreateIndex(
                name: "IX_kyb_verifications_CompanyInstallationId_RegistrationNumber",
                schema: "neobanking",
                table: "kyb_verifications",
                columns: new[] { "CompanyInstallationId", "RegistrationNumber" });

            migrationBuilder.CreateIndex(
                name: "IX_kyb_verifications_CompanyInstallationId_Status",
                schema: "neobanking",
                table: "kyb_verifications",
                columns: new[] { "CompanyInstallationId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_kyb_verifications_OnboardingApplicationId",
                schema: "neobanking",
                table: "kyb_verifications",
                column: "OnboardingApplicationId");

            migrationBuilder.CreateIndex(
                name: "IX_kyc_verifications_CompanyInstallationId",
                schema: "neobanking",
                table: "kyc_verifications",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_kyc_verifications_CompanyInstallationId_Provider_ProviderRe~",
                schema: "neobanking",
                table: "kyc_verifications",
                columns: new[] { "CompanyInstallationId", "Provider", "ProviderReference" });

            migrationBuilder.CreateIndex(
                name: "IX_kyc_verifications_CompanyInstallationId_UserId_Status",
                schema: "neobanking",
                table: "kyc_verifications",
                columns: new[] { "CompanyInstallationId", "UserId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_kyc_verifications_OnboardingApplicationId",
                schema: "neobanking",
                table: "kyc_verifications",
                column: "OnboardingApplicationId");

            migrationBuilder.CreateIndex(
                name: "IX_kyc_verifications_UserId",
                schema: "neobanking",
                table: "kyc_verifications",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_onboarding_applications_ApplicantUserId",
                schema: "neobanking",
                table: "onboarding_applications",
                column: "ApplicantUserId");

            migrationBuilder.CreateIndex(
                name: "IX_onboarding_applications_CompanyInstallationId",
                schema: "neobanking",
                table: "onboarding_applications",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_onboarding_applications_CompanyInstallationId_Kind_Status",
                schema: "neobanking",
                table: "onboarding_applications",
                columns: new[] { "CompanyInstallationId", "Kind", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_provider_mappings_CompanyInstallationId",
                schema: "neobanking",
                table: "provider_mappings",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_provider_mappings_CompanyInstallationId_InternalEntityType_~",
                schema: "neobanking",
                table: "provider_mappings",
                columns: new[] { "CompanyInstallationId", "InternalEntityType", "InternalEntityId" });

            migrationBuilder.CreateIndex(
                name: "IX_provider_mappings_CompanyInstallationId_Provider_ProviderEn~",
                schema: "neobanking",
                table: "provider_mappings",
                columns: new[] { "CompanyInstallationId", "Provider", "ProviderEntityType", "ProviderEntityId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_refresh_sessions_CompanyInstallationId",
                schema: "neobanking",
                table: "refresh_sessions",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_sessions_CompanyInstallationId_UserId_ExpiresAt",
                schema: "neobanking",
                table: "refresh_sessions",
                columns: new[] { "CompanyInstallationId", "UserId", "ExpiresAt" });

            migrationBuilder.CreateIndex(
                name: "IX_refresh_sessions_RevokedAt",
                schema: "neobanking",
                table: "refresh_sessions",
                column: "RevokedAt");

            migrationBuilder.CreateIndex(
                name: "IX_refresh_sessions_TokenHash",
                schema: "neobanking",
                table: "refresh_sessions",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_refresh_sessions_UserId",
                schema: "neobanking",
                table: "refresh_sessions",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_user_identities_CompanyInstallationId",
                schema: "neobanking",
                table: "user_identities",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_user_identities_CompanyInstallationId_Provider_Subject",
                schema: "neobanking",
                table: "user_identities",
                columns: new[] { "CompanyInstallationId", "Provider", "Subject" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_user_identities_UserId_IsPrimary",
                schema: "neobanking",
                table: "user_identities",
                columns: new[] { "UserId", "IsPrimary" });

            migrationBuilder.CreateIndex(
                name: "IX_users_CompanyInstallationId",
                schema: "neobanking",
                table: "users",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_users_CompanyInstallationId_EmailNormalized",
                schema: "neobanking",
                table: "users",
                columns: new[] { "CompanyInstallationId", "EmailNormalized" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_users_CompanyInstallationId_Status",
                schema: "neobanking",
                table: "users",
                columns: new[] { "CompanyInstallationId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_webhook_deliveries_CompanyInstallationId",
                schema: "neobanking",
                table: "webhook_deliveries",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_webhook_deliveries_CompanyInstallationId_Provider_EventId",
                schema: "neobanking",
                table: "webhook_deliveries",
                columns: new[] { "CompanyInstallationId", "Provider", "EventId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_webhook_deliveries_CompanyInstallationId_Status_NextAttempt~",
                schema: "neobanking",
                table: "webhook_deliveries",
                columns: new[] { "CompanyInstallationId", "Status", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_webhook_deliveries_IdempotencyKey",
                schema: "neobanking",
                table: "webhook_deliveries",
                column: "IdempotencyKey");

            migrationBuilder.CreateIndex(
                name: "IX_webhook_deliveries_WebhookEndpointId",
                schema: "neobanking",
                table: "webhook_deliveries",
                column: "WebhookEndpointId");

            migrationBuilder.CreateIndex(
                name: "IX_webhook_endpoints_CompanyInstallationId",
                schema: "neobanking",
                table: "webhook_endpoints",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_webhook_endpoints_CompanyInstallationId_Provider_Url",
                schema: "neobanking",
                table: "webhook_endpoints",
                columns: new[] { "CompanyInstallationId", "Provider", "Url" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_webhook_endpoints_CompanyInstallationId_Status",
                schema: "neobanking",
                table: "webhook_endpoints",
                columns: new[] { "CompanyInstallationId", "Status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "admin_profiles",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "audit_log_entries",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "banking_snapshots",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "cards",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "idempotency_records",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "kyb_verifications",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "kyc_verifications",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "provider_mappings",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "refresh_sessions",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "user_identities",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "webhook_deliveries",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "onboarding_applications",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "webhook_endpoints",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "users",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "company_installations",
                schema: "neobanking");
        }
    }
}
