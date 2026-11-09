ARG TARGET
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble AS build-coreclr
WORKDIR /src
COPY csharp/EnumDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -o /app --no-self-contained
FROM mcr.microsoft.com/dotnet/sdk:10.0.403-noble-aot AS build-native
WORKDIR /src
COPY csharp/EnumDispatch.csproj csharp/Program.cs ./
RUN dotnet publish -c Release -r linux-x64 -p:PublishAot=true -o /app
FROM mcr.microsoft.com/dotnet/runtime:10.0.14-noble AS final-coreclr
COPY --from=build-coreclr /app /app
ENTRYPOINT ["dotnet", "/app/EnumDispatch.dll"]
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0.14-noble AS final-dotnet-native
COPY --from=build-native /app/EnumDispatch /enum-dispatch
ENTRYPOINT ["/enum-dispatch"]
FROM final-${TARGET}
