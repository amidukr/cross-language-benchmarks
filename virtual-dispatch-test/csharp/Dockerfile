ARG TARGET
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble AS build-coreclr
WORKDIR /src
COPY csharp/VirtualDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -o /app --no-self-contained
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble-aot AS build-native
WORKDIR /src
COPY csharp/VirtualDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -r linux-x64 -p:PublishAot=true -o /app
FROM mcr.microsoft.com/dotnet/runtime:10.0.14-noble AS final-coreclr
COPY --from=build-coreclr /app /app
ENTRYPOINT ["dotnet", "/app/VirtualDispatch.dll"]
FROM docker.io/library/debian:bookworm-20251020-slim AS final-dotnet-native
COPY --from=build-native /app/VirtualDispatch /virtual-dispatch
ENTRYPOINT ["/virtual-dispatch"]
FROM final-${TARGET}
