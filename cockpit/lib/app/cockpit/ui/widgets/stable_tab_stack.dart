import 'package:flutter/widgets.dart';

/// IndexedStack inserts unkeyed Visibility wrappers around its children.
/// Removing a preceding tab can recreate a keyed child's parent and reparent
/// a native view before its render object receives the new attachment.
/// Key the presentation host itself so remaining tabs never deactivate.
class StableTabStack extends StatelessWidget {
  const StableTabStack({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (var i = 0; i < children.length; i++)
        Offstage(
          key: children[i].key,
          offstage: i != index,
          child: ExcludeFocus(
            excluding: i != index,
            child: TickerMode(enabled: i == index, child: children[i]),
          ),
        ),
    ],
  );
}
