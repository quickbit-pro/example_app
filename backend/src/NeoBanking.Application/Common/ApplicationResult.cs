using System;

namespace NeoBanking.Application.Common;

public sealed class ApplicationResult<T>
{
    private ApplicationResult(T value)
    {
        Value = value;
    }

    private ApplicationResult(ApplicationError error)
    {
        Error = error;
    }

    public bool IsSuccess => Error is null;

    public T? Value { get; }

    public ApplicationError? Error { get; }

    public static ApplicationResult<T> Success(T value) => new(value);

    public static ApplicationResult<T> Failure(ApplicationError error)
    {
        ArgumentNullException.ThrowIfNull(error);
        return new ApplicationResult<T>(error);
    }
}
