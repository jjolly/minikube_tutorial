using Dapper;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("JournalDb")
    ?? throw new InvalidOperationException("Missing JournalDb connection string.");

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
    });
});

var app = builder.Build();
app.UseCors();

app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

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

record Entry(int Id, string Title, string Body, DateTime CreatedAt);
record CreateEntryRequest(string Title, string Body);
