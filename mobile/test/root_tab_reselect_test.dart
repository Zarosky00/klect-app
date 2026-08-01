import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/features/shell/root_shell.dart';

void main() {
  test('consecutive active-tab taps publish distinct reselect events', () {
    final container = ProviderContainer.test();
    final notifier = container.read(rootTabReselectProvider.notifier);

    notifier.reselect(4);
    final first = container.read(rootTabReselectProvider)!;
    notifier.reselect(4);
    final second = container.read(rootTabReselectProvider)!;

    expect(first.index, 4);
    expect(second.index, 4);
    expect(second.serial, first.serial + 1);
  });
}
