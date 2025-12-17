# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy csproj and restore dependencies
COPY ["src/BranchApi/BranchApi.csproj", "BranchApi/"]
RUN dotnet restore "BranchApi/BranchApi.csproj"

# Copy everything else and build
COPY src/BranchApi/. BranchApi/
WORKDIR "/src/BranchApi"
RUN dotnet build "BranchApi.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "BranchApi.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "BranchApi.dll"]
