using System.ComponentModel.DataAnnotations;

namespace NeoBanking.Application.DTOs.Mor;

public sealed class MorUserRequest
{
    public MorUserRequest() { }
    public MorUserRequest(string email, string firstName, string lastName, string password, string phone)
    {
        Email = email;
        FirstName = firstName;
        LastName = lastName;
        Password = password;
        Phone = phone;
    }
    [Required, EmailAddress]
    public string Email { get; init; } = string.Empty;
    [Required]
    public string FirstName { get; init; } = string.Empty;
    [Required]
    public string LastName { get; init; } = string.Empty;
    [Required, RegularExpression(@"^\+[1-9][0-9]{7,14}$", ErrorMessage = "Enter a phone number with its country code, including +, without spaces.")]
    public string Phone { get; init; } = string.Empty;
    [Required, MinLength(8)]
    public string Password { get; init; } = string.Empty;
}

public sealed class MorCompanyRequest
{
    public MorCompanyRequest() { }
    public MorCompanyRequest(string companyName, string legalName, string? registrationNumber, string? country, string adminEmail, string adminFirstName, string adminLastName, string adminPassword, int tierId)
    {
        CompanyName = companyName;
        LegalName = legalName;
        RegistrationNumber = registrationNumber;
        Country = country;
        AdminEmail = adminEmail;
        AdminFirstName = adminFirstName;
        AdminLastName = adminLastName;
        AdminPassword = adminPassword;
        TierId = tierId;
    }
    [Required]
    public string CompanyName { get; init; } = string.Empty;
    [Required]
    public string LegalName { get; init; } = string.Empty;
    public string? RegistrationNumber { get; init; }
    public string? Country { get; init; }
    [Required, EmailAddress]
    public string AdminEmail { get; init; } = string.Empty;
    [Required]
    public string AdminFirstName { get; init; } = string.Empty;
    [Required]
    public string AdminLastName { get; init; } = string.Empty;
    [Required, MinLength(8)]
    public string AdminPassword { get; init; } = string.Empty;
    [Range(1, int.MaxValue)]
    public int TierId { get; init; }
}

public sealed class MorOrderRequest
{
    public MorOrderRequest() { }
    public MorOrderRequest(int cardTypeId, int quantity, bool autoLockEnabled, string? labelPrefix)
    {
        CardTypeId = cardTypeId;
        Quantity = quantity;
        AutoLockEnabled = autoLockEnabled;
        LabelPrefix = labelPrefix;
    }
    [Range(1, int.MaxValue)]
    public int CardTypeId { get; init; }
    [Range(1, 20)]
    public int Quantity { get; init; }
    public bool AutoLockEnabled { get; init; }
    public string? LabelPrefix { get; init; }
}

public sealed class MorAssignRequest
{
    public MorAssignRequest() { }
    public MorAssignRequest(int assignedUserId)
    {
        AssignedUserId = assignedUserId;
    }
    [Range(1, int.MaxValue)]
    public int AssignedUserId { get; init; }
}

public sealed class MorFundingRequest
{
    public MorFundingRequest() { }
    public MorFundingRequest(decimal amount)
    {
        Amount = amount;
    }
    [Range(typeof(decimal), "0.01", "999999999999", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)]
    public decimal Amount { get; init; }
}

public sealed class MorCardholderRequest
{
    public MorCardholderRequest() { }
    public MorCardholderRequest(string? dob)
    {
        Dob = dob;
    }
    public string? Dob { get; init; }
}

public sealed class MorQuantumTransferRequest
{
    public MorQuantumTransferRequest() { }
    public MorQuantumTransferRequest(string sourceCurrency, string destinationCurrency, decimal amount)
    {
        SourceCurrency = sourceCurrency;
        DestinationCurrency = destinationCurrency;
        Amount = amount;
    }
    [Required]
    public string SourceCurrency { get; init; } = string.Empty;
    [Required]
    [RegularExpression("^USD$")]
    public string DestinationCurrency { get; init; } = string.Empty;
    [Range(typeof(decimal), "0.01", "999999999999", ParseLimitsInInvariantCulture = true, ConvertValueInInvariantCulture = true)]
    public decimal Amount { get; init; }
}

public sealed class MorUboRequest
{
    public MorUboRequest() { }
    public MorUboRequest(string uboFirstName, string uboLastName, string uboGender, string uboCountryCode, string uboIdType, string uboIdNumber, string uboDob)
    {
        UboFirstName = uboFirstName;
        UboLastName = uboLastName;
        UboGender = uboGender;
        UboCountryCode = uboCountryCode;
        UboIdType = uboIdType;
        UboIdNumber = uboIdNumber;
        UboDob = uboDob;
    }
    [Required]
    public string UboFirstName { get; init; } = string.Empty;
    [Required]
    public string UboLastName { get; init; } = string.Empty;
    [Required]
    public string UboGender { get; init; } = string.Empty;
    [Required]
    public string UboCountryCode { get; init; } = string.Empty;
    [Required]
    public string UboIdType { get; init; } = string.Empty;
    [Required]
    public string UboIdNumber { get; init; } = string.Empty;
    [Required]
    public string UboDob { get; init; } = string.Empty;
}

public sealed class MorKybRequest
{
    public MorKybRequest() { }
    public MorKybRequest(string companyName, string registrationNumber, string registrationCountry, string industry, string website, MorUboRequest uboInformation)
    {
        CompanyName = companyName;
        RegistrationNumber = registrationNumber;
        RegistrationCountry = registrationCountry;
        Industry = industry;
        Website = website;
        UboInformation = uboInformation;
    }
    [Required]
    public string CompanyName { get; init; } = string.Empty;
    [Required]
    public string RegistrationNumber { get; init; } = string.Empty;
    [Required]
    public string RegistrationCountry { get; init; } = string.Empty;
    [Required]
    public string Industry { get; init; } = string.Empty;
    [Required, Url]
    public string Website { get; init; } = string.Empty;
    [Required]
    public MorUboRequest UboInformation { get; init; } = null!;
}
