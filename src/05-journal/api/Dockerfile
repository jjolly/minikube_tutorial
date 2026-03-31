FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY JournalApi.csproj ./
RUN dotnet restore JournalApi.csproj
COPY Program.cs ./
COPY appsettings.json ./
RUN dotnet publish JournalApi.csproj -c Release -o /out

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
COPY --from=build /out ./
EXPOSE 8080
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
CMD ["dotnet", "JournalApi.dll"]
