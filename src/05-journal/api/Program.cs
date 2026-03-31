using Dapper;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("JournalDb")
    ?? throw new InvalidOperationException("Missing JournalDb connection string.");

var autoMigrate = builder.Configuration.GetValue("Journal:AutoMigrate", false);

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
    });
});

if (autoMigrate)
{
    await EnsureJournalSchemaAsync(connectionString);
}

var app = builder.Build();
app.UseCors();

app.MapGet("/healthz", () => Results.Ok(new { status = "ok", autoMigrate }));

app.MapGet("/api/entries", async () =>
{
    await using var conn = new SqlConnection(connectionString);
    var rows = await conn.QueryAsync<Entry>(
        "SELECT Id, Title, Body, CreatedAt FROM dbo.Entries ORDER BY CreatedAt DESC");
    return Results.Ok(rows);
});

app.MapGet("/api/entries/{id:int}", async (int id) =>
{
    await using var conn = new SqlConnection(connectionString);
    var row = await conn.QuerySingleOrDefaultAsync<Entry>(
        "SELECT Id, Title, Body, CreatedAt FROM dbo.Entries WHERE Id = @id", new { id });
    return row is null ? Results.NotFound() : Results.Ok(row);
});

app.MapPost("/api/entries", async (CreateEntryRequest request) =>
{
    await using var conn = new SqlConnection(connectionString);
    var id = await conn.ExecuteScalarAsync<int>(@"
        INSERT INTO dbo.Entries (Title, Body)
        OUTPUT INSERTED.Id
        VALUES (@Title, @Body);", request);
    return Results.Created($"/api/entries/{id}", new { id });
});

app.Run();

static async Task EnsureJournalSchemaAsync(string journalConnectionString)
{
    var builder = new SqlConnectionStringBuilder(journalConnectionString);
    var databaseName = builder.InitialCatalog;
    if (string.IsNullOrWhiteSpace(databaseName))
    {
        throw new InvalidOperationException("JournalDb connection string must include a database name.");
    }

    var masterBuilder = new SqlConnectionStringBuilder(journalConnectionString)
    {
        InitialCatalog = "master"
    };

    await using (var masterConn = new SqlConnection(masterBuilder.ConnectionString))
    {
        await masterConn.OpenAsync();
        var createDbSql = $@"
IF DB_ID(N'{databaseName.Replace("'", "''")}') IS NULL
BEGIN
    CREATE DATABASE [{databaseName.Replace("]", "]]")}] ;
END;";
        await masterConn.ExecuteAsync(createDbSql);
    }

    await using (var journalConn = new SqlConnection(journalConnectionString))
    {
        await journalConn.OpenAsync();
        var createTableSql = @"
IF OBJECT_ID(N'dbo.Entries', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Entries (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        Title NVARCHAR(200) NOT NULL,
        Body NVARCHAR(MAX) NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;";
        await journalConn.ExecuteAsync(createTableSql);
    }
}

record Entry(int Id, string Title, string Body, DateTime CreatedAt);
record CreateEntryRequest(string Title, string Body);
