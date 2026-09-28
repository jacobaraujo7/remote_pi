import 'package:cockpit/app/cockpit/domain/entities/panel_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a full frontmatter and keeps the html body', () {
    final doc = PanelDocument.parse(
      '---\n'
      'title: "Repo status"   # tab label\n'
      'reload: false\n'
      'cwd: ../app\n'
      'extra: 42\n'
      '---\n'
      '<!doctype html>\n<p>hi</p>\n',
    );
    expect(doc.title, 'Repo status');
    expect(doc.reload, isFalse);
    expect(doc.cwd, '../app');
    expect(doc.fields['extra'], '42');
    expect(doc.body, '<!doctype html>\n<p>hi</p>\n');
  });

  test('partial frontmatter falls back to defaults', () {
    final doc = PanelDocument.parse('---\ntitle: X\n---\n<b>a</b>');
    expect(doc.title, 'X');
    expect(doc.reload, isTrue);
    expect(doc.cwd, isNull);
    expect(doc.body, '<b>a</b>');
  });

  test('no frontmatter = whole file is the body', () {
    const raw = '<!doctype html>\n<hr>\n---\nnot a fence\n';
    final doc = PanelDocument.parse(raw);
    expect(doc.title, isNull);
    expect(doc.body, raw);
  });

  test('an unclosed --- is not a frontmatter', () {
    const raw = '---\n<p>lonely dash line</p>\n';
    expect(PanelDocument.parse(raw).body, raw);
  });

  test('strips a BOM before looking for the fence', () {
    final doc = PanelDocument.parse('﻿---\ntitle: T\n---\n<i/>');
    expect(doc.title, 'T');
  });
}
