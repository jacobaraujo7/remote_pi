import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_detector.dart';
import 'package:cockpit/app/cockpit/domain/dotnet/dotnet_solution_parser.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = DotnetSolutionParser();

  test('nested sln keeps projects inside the solution folder', () {
    const sln = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Domain", "src\\Domain\\Domain.csproj", "{CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "src\\App\\App.csproj", "{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}"
EndProject
Global
	GlobalSection(NestedProjects) = preSolution
		{CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC} = {AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}
		{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB} = {AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA}
	EndGlobalSection
EndGlobal
''';
    final snapshot = parser.parse(
      solutionPath: '/ws/Demo.sln',
      solutionText: sln,
      projectTexts: const {},
    );
    expect(snapshot, isNotNull);
    final root = snapshot!.root;
    expect(root.name, 'Demo');
    expect(root.projectCount, 2);
    expect(root.children, hasLength(1));
    final folder = root.children.single;
    expect(folder.kind, DotnetNodeKind.solutionFolder);
    expect(folder.name, 'src');
    expect(folder.projectCount, 2);
    expect(folder.children.map((node) => node.name), ['App', 'Domain']);
    expect(folder.children.first.path, '/ws/src/App/App.csproj');
  });

  test('slnx reads folders, projects and solution files', () {
    const slnx = '''
<Solution>
  <File Path="README.md" />
  <Folder Name="/src/">
    <Project Path="src/Zebra/Zebra.csproj" />
    <Project Path="src/App/App.csproj" />
  </Folder>
</Solution>
''';
    final snapshot = parser.parse(
      solutionPath: '/ws/Demo.slnx',
      solutionText: slnx,
      projectTexts: const {},
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.root.children.map((node) => node.name), [
      'src',
      'README.md',
    ]);
    final src = snapshot.root.children.first;
    expect(src.children.map((node) => node.name), ['App', 'Zebra']);
    expect(src.children.first.path, '/ws/src/App/App.csproj');
  });

  test('project lists linked folders before files, both alphabetical', () {
    const sln = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "src\\App\\App.csproj", "{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}"
EndProject
''';
    const csproj = '''
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Serilog" Version="4.0.0" />
    <ProjectReference Include="..\\Domain\\Domain.csproj" />
    <Compile Include="..\\Other\\Aaa.cs" Link="Aaa.cs" />
    <Compile Include="..\\Shared\\Util.cs" Link="Shared\\Util.cs" />
    <Folder Include="Zebra\\" />
    <Folder Include="Empty\\" />
  </ItemGroup>
</Project>
''';
    final projectPath = '/ws/src/App/App.csproj';
    final snapshot = parser.parse(
      solutionPath: '/ws/Demo.sln',
      solutionText: sln,
      projectTexts: {projectPath: csproj},
    );
    final project = snapshot!.root.children.single;
    expect(project.children.map((node) => node.name), [
      'Empty',
      'Shared',
      'Zebra',
      'Aaa.cs',
    ]);
    final shared = project.children[1];
    expect(shared.kind, DotnetNodeKind.folder);
    expect(shared.children.single.path, '/ws/src/Shared/Util.cs');
  });

  test('invalid solution xml returns null and a broken project stays', () {
    expect(
      parser.parse(
        solutionPath: '/ws/Demo.slnx',
        solutionText: '<Solution>',
        projectTexts: const {},
      ),
      isNull,
    );
    const sln = '''
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "App", "App.csproj", "{BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB}"
EndProject
''';
    final snapshot = parser.parse(
      solutionPath: '/ws/Demo.sln',
      solutionText: sln,
      projectTexts: const {'/ws/App.csproj': '<Project>'},
    );
    expect(snapshot, isNotNull);
    expect(snapshot!.root.children.single.name, 'App');
    expect(snapshot.root.children.single.children, isEmpty);
  });

  test(
    'detection skips build folders and prefers the shallow solution',
    () async {
      final tree = <String, List<FileNode>>{
        '/ws': [
          const FileNode(name: 'src', path: '/ws/src', isDirectory: true),
          const FileNode(name: 'bin', path: '/ws/bin', isDirectory: true),
          const FileNode(
            name: 'App.sln',
            path: '/ws/App.sln',
            isDirectory: false,
          ),
        ],
        '/ws/src': [
          const FileNode(
            name: 'Lib.slnx',
            path: '/ws/src/Lib.slnx',
            isDirectory: false,
          ),
        ],
        '/ws/bin': [
          const FileNode(
            name: 'Hidden.sln',
            path: '/ws/bin/Hidden.sln',
            isDirectory: false,
          ),
        ],
      };
      final found = await detectDotnetSolutions(
        '/ws',
        (path) async => tree[path] ?? const [],
      );
      expect(found.map((ref) => ref.path), ['/ws/App.sln', '/ws/src/Lib.slnx']);
    },
  );
}
