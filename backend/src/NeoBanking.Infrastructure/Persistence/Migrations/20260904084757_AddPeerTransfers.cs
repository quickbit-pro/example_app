using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NeoBanking.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddPeerTransfers : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "peer_contacts",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    ContactUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Nickname = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_peer_contacts", x => x.Id);
                    table.ForeignKey(
                        name: "FK_peer_contacts_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_peer_contacts_users_ContactUserId",
                        column: x => x.ContactUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_peer_contacts_users_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "peer_payment_requests",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    RequesterUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    PayerUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(24,8)", nullable: false),
                    Currency = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    Note = table.Column<string>(type: "character varying(250)", maxLength: 250, nullable: true),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    RespondedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    TransferId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_peer_payment_requests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_peer_payment_requests_company_installations_CompanyInstalla~",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_peer_payment_requests_users_PayerUserId",
                        column: x => x.PayerUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_peer_payment_requests_users_RequesterUserId",
                        column: x => x.RequesterUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "peer_transfers",
                schema: "neobanking",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    SenderUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    RecipientUserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<decimal>(type: "numeric(24,8)", nullable: false),
                    Currency = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    Note = table.Column<string>(type: "character varying(250)", maxLength: 250, nullable: true),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    FeeAmount = table.Column<decimal>(type: "numeric(24,8)", nullable: false),
                    ExternalReferenceId = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    DebitTransferId = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    CreditTransferId = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    RefundTransferId = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    PaymentRequestId = table.Column<Guid>(type: "uuid", nullable: true),
                    ErrorCode = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    CompanyInstallationId = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_peer_transfers", x => x.Id);
                    table.ForeignKey(
                        name: "FK_peer_transfers_company_installations_CompanyInstallationId",
                        column: x => x.CompanyInstallationId,
                        principalSchema: "neobanking",
                        principalTable: "company_installations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_peer_transfers_users_RecipientUserId",
                        column: x => x.RecipientUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_peer_transfers_users_SenderUserId",
                        column: x => x.SenderUserId,
                        principalSchema: "neobanking",
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_peer_contacts_CompanyInstallationId",
                schema: "neobanking",
                table: "peer_contacts",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_contacts_CompanyInstallationId_OwnerUserId_ContactUser~",
                schema: "neobanking",
                table: "peer_contacts",
                columns: new[] { "CompanyInstallationId", "OwnerUserId", "ContactUserId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_peer_contacts_ContactUserId",
                schema: "neobanking",
                table: "peer_contacts",
                column: "ContactUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_contacts_OwnerUserId",
                schema: "neobanking",
                table: "peer_contacts",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_payment_requests_CompanyInstallationId",
                schema: "neobanking",
                table: "peer_payment_requests",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_payment_requests_CompanyInstallationId_PayerUserId_Sta~",
                schema: "neobanking",
                table: "peer_payment_requests",
                columns: new[] { "CompanyInstallationId", "PayerUserId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_peer_payment_requests_CompanyInstallationId_RequesterUserId~",
                schema: "neobanking",
                table: "peer_payment_requests",
                columns: new[] { "CompanyInstallationId", "RequesterUserId", "Status" });

            migrationBuilder.CreateIndex(
                name: "IX_peer_payment_requests_PayerUserId",
                schema: "neobanking",
                table: "peer_payment_requests",
                column: "PayerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_payment_requests_RequesterUserId",
                schema: "neobanking",
                table: "peer_payment_requests",
                column: "RequesterUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_CompanyInstallationId",
                schema: "neobanking",
                table: "peer_transfers",
                column: "CompanyInstallationId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_CompanyInstallationId_RecipientUserId_Create~",
                schema: "neobanking",
                table: "peer_transfers",
                columns: new[] { "CompanyInstallationId", "RecipientUserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_CompanyInstallationId_SenderUserId_CreatedAt",
                schema: "neobanking",
                table: "peer_transfers",
                columns: new[] { "CompanyInstallationId", "SenderUserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_ExternalReferenceId",
                schema: "neobanking",
                table: "peer_transfers",
                column: "ExternalReferenceId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_RecipientUserId",
                schema: "neobanking",
                table: "peer_transfers",
                column: "RecipientUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_SenderUserId",
                schema: "neobanking",
                table: "peer_transfers",
                column: "SenderUserId");

            migrationBuilder.CreateIndex(
                name: "IX_peer_transfers_Status",
                schema: "neobanking",
                table: "peer_transfers",
                column: "Status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "peer_contacts",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "peer_payment_requests",
                schema: "neobanking");

            migrationBuilder.DropTable(
                name: "peer_transfers",
                schema: "neobanking");
        }
    }
}
