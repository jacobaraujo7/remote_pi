import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_cache.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_parser.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingParser extends DotnetSolutionParser {
  int parses = 0;

  @override
  DotnetSolutionSnapshot? parse({
    required String solutionPath,
    required String solutionText,
    required Map<String, String> projectTexts,
  }) {
    parses++;
    return super.parse(
      solutionPath: solutionPath,
      solutionText: solutionText,
      projectTexts: projectTexts,
    );
  }
}

void main() {
  const sln = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "App.csproj", "{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}"
EndProject
''';
  const csproj = '''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageReference Include="Serilog" Version="4.0.0" /></ItemGroup>
</Project>
''';

  DotnetSolutionSnapshot snap(String name) {
    return DotnetSolutionSnapshot(
      path: '/unused',
      name: name,
      fingerprint: '',
      projectPaths: const [],
      root: DotnetNode(id: name, kind: DotnetNodeKind.solution, name: name),
    );
  }

  test('two worktrees keep separate models', () {
    final cache = DotnetSolutionCache();
    cache.putModel('/wt1/App.sln', 'a', snap('One'));
    cache.putModel('/wt2/App.sln', 'a', snap('Two'));
    expect(cache.peek('/wt1/App.sln')!.name, 'One');
    expect(cache.peek('/wt2/App.sln')!.name, 'Two');
  });

  test('same fingerprint does not parse again', () async {
    final cache = DotnetSolutionCache();
    final parser = _CountingParser();
    final files = <String, String>{
      '/wt/App.sln': sln,
      '/wt/App.csproj': csproj,
    };
    Future<String?> read(String path) async => files[path];

    final first = await loadCachedDotnetSolution(
      cache: cache,
      path: '/wt/App.sln',
      read: read,
      parser: parser,
    );
    final second = await loadCachedDotnetSolution(
      cache: cache,
      path: '/wt/App.sln',
      read: read,
      parser: parser,
    );
    expect(identical(first, second), isTrue);
    expect(parser.parses, 1);

    files['/wt/App.csproj'] = csproj.replaceAll('Serilog', 'NLog');
    final third = await loadCachedDotnetSolution(
      cache: cache,
      path: '/wt/App.sln',
      read: read,
      parser: parser,
    );
    expect(identical(first, third), isFalse);
    expect(parser.parses, 2);
    expect(third!.root.children.single.name, 'App');
  });

  test('expansion is stored per solution path', () {
    final cache = DotnetSolutionCache();
    cache.seedExpansion('/wt1/App.sln', {'sln', 'proj'});
    cache.toggleExpanded('/wt1/App.sln', 'proj');
    cache.seedExpansion('/wt2/App.sln', {'other'});
    expect(cache.expansion('/wt1/App.sln'), {'sln'});
    expect(cache.expansion('/wt2/App.sln'), {'other'});
    cache.collapse('/wt1/App.sln');
    expect(cache.expansion('/wt1/App.sln'), isEmpty);
    expect(cache.hasExpansion('/wt1/App.sln'), isTrue);
  });
}
