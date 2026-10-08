namespace NeoBanking.Application.Company;

internal sealed class CompanyContextAccessor : ICompanyContextAccessor
{
    private ICompanyContext _current = CompanyContext.Empty;

    public ICompanyContext Current => _current;

    public void SetCurrent(ICompanyContext context)
    {
        ArgumentNullException.ThrowIfNull(context);
        _current = context;
    }

    public void Clear()
    {
        _current = CompanyContext.Empty;
    }
}
