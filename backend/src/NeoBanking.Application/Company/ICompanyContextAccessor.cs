namespace NeoBanking.Application.Company;

public interface ICompanyContextAccessor
{
    ICompanyContext Current { get; }

    void SetCurrent(ICompanyContext context);

    void Clear();
}
