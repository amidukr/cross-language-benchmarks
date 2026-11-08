ARG TARGET
FROM mcr.microsoft.com/dotnet/sdk:10.0.100-bookworm-slim AS build-coreclr
WORKDIR /src
COPY csharp/VirtualDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -o /app --no-self-contained
FROM mcr.microsoft.com/dotnet/sdk:10.0.100-bookworm-slim AS build-native
RUN apt-get update && apt-get install -y --no-install-recommends clang zlib1g-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY csharp/VirtualDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -r linux-x64 -p:PublishAot=true -o /app
FROM mcr.microsoft.com/dotnet/runtime:10.0.0-bookworm-slim AS final-coreclr
COPY --from=build-coreclr /app /app
ENTRYPOINT ["dotnet", "/app/VirtualDispatch.dll"]
FROM docker.io/library/debian:bookworm-20251020-slim AS final-dotnet-native
COPY --from=build-native /app/VirtualDispatch /virtual-dispatch
ENTRYPOINT ["/virtual-dispatch"]
FROM final-${TARGET}
