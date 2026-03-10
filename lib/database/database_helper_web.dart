Future<String> platformGetAppDirectoryPath() async => '';

Future<List<String>> platformFindExistingDatabases() async => [];

Future<void> platformRemoveDatabase(String path,
    {bool deleteFile = false}) async {}

Future<void> platformAddRecentDatabase(String path) async {}
