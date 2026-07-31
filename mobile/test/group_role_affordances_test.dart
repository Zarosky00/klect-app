import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/chat/group_info_screen.dart';

/// The three Member_Role values in rank order, least privileged first.
const List<String> _rolesByRank = <String>['member', 'admin', 'owner'];

/// The role-change affordances the Group_Info_Screen offers must match the
/// widened `set_group_member_role` RPC clause for clause, so the screen never
/// offers a change the server refuses (Requirements 13.5, 13.6).
GroupRoleAffordances affordances(
  String? viewerRole,
  String targetRole, {
  bool isSelf = false,
}) => GroupRoleAffordances(
  viewerRole: viewerRole,
  targetRole: targetRole,
  isSelf: isSelf,
);

void main() {
  group('promotion and demotion are open to admins as well as the owner', () {
    test('the owner may promote a member', () {
      final a = affordances('owner', 'member');
      expect(a.canPromoteToAdmin, isTrue);
      expect(a.canDemoteToMember, isFalse);
    });

    test('an admin may promote a member', () {
      final a = affordances('admin', 'member');
      expect(a.canPromoteToAdmin, isTrue);
      expect(a.canDemoteToMember, isFalse);
    });

    test('the owner may demote an admin', () {
      final a = affordances('owner', 'admin');
      expect(a.canDemoteToMember, isTrue);
      expect(a.canPromoteToAdmin, isFalse);
    });

    test('an admin may demote another admin', () {
      final a = affordances('admin', 'admin');
      expect(a.canDemoteToMember, isTrue);
      expect(a.canPromoteToAdmin, isFalse);
    });

    test('a plain member may change nothing', () {
      for (final targetRole in const <String>['owner', 'admin', 'member']) {
        expect(affordances('member', targetRole).any, isFalse);
      }
    });

    test('a non-member may change nothing', () {
      for (final targetRole in const <String>['owner', 'admin', 'member']) {
        expect(affordances(null, targetRole).any, isFalse);
      }
    });
  });

  group('the owner is never a target', () {
    test('an owner target offers no action to an admin', () {
      expect(affordances('admin', 'owner').any, isFalse);
    });

    test('an owner target offers no action to an owner', () {
      expect(affordances('owner', 'owner').any, isFalse);
    });
  });

  group('ownership transfer stays owner-only', () {
    test('the owner may transfer to an admin or a member', () {
      expect(affordances('owner', 'admin').canTransferOwnership, isTrue);
      expect(affordances('owner', 'member').canTransferOwnership, isTrue);
    });

    test('an admin may not transfer ownership', () {
      expect(affordances('admin', 'admin').canTransferOwnership, isFalse);
      expect(affordances('admin', 'member').canTransferOwnership, isFalse);
    });
  });

  test('nobody manages their own row', () {
    for (final viewerRole in const <String>['owner', 'admin', 'member']) {
      expect(affordances(viewerRole, viewerRole, isSelf: true).any, isFalse);
    }
  });

  test('removal follows the same admin-and-never-the-owner rule', () {
    expect(affordances('owner', 'member').canRemove, isTrue);
    expect(affordances('admin', 'member').canRemove, isTrue);
    expect(affordances('admin', 'admin').canRemove, isTrue);
    expect(affordances('admin', 'owner').canRemove, isFalse);
    expect(affordances('member', 'member').canRemove, isFalse);
  });

  test('an unknown wire role is treated as the least privileged', () {
    // A role the client does not know is not an admin and not an owner: it can
    // be managed like a member, and it grants its holder nothing.
    expect(affordances('curator', 'member').any, isFalse);
    expect(affordances('admin', 'curator').canRemove, isTrue);
    expect(affordances('admin', 'curator').canPromoteToAdmin, isTrue);
    expect(affordances('admin', 'curator').canDemoteToMember, isFalse);
  });

  // ── Requirement 13.10: scope evaluation is monotone in Member_Role rank ──

  group('GroupPermissionScope.allows is monotone in role rank', () {
    test('ranks order member below admin below owner', () {
      expect(
        GroupPermissionScope.rankOf('member'),
        lessThan(GroupPermissionScope.rankOf('admin')),
      );
      expect(
        GroupPermissionScope.rankOf('admin'),
        lessThan(GroupPermissionScope.rankOf('owner')),
      );
    });

    test('every scope that permits a role permits every higher role', () {
      for (final scope in GroupPermissionScope.values) {
        for (var lower = 0; lower < _rolesByRank.length; lower++) {
          if (!scope.allows(_rolesByRank[lower])) continue;
          for (var higher = lower + 1; higher < _rolesByRank.length; higher++) {
            expect(
              scope.allows(_rolesByRank[higher]),
              isTrue,
              reason:
                  '$scope permits ${_rolesByRank[lower]} but refuses '
                  '${_rolesByRank[higher]}, which outranks it',
            );
          }
        }
      }
    });

    test('the three scopes evaluate to their documented sets', () {
      expect(GroupPermissionScope.owner.allows('owner'), isTrue);
      expect(GroupPermissionScope.owner.allows('admin'), isFalse);
      expect(GroupPermissionScope.owner.allows('member'), isFalse);

      expect(GroupPermissionScope.admins.allows('owner'), isTrue);
      expect(GroupPermissionScope.admins.allows('admin'), isTrue);
      expect(GroupPermissionScope.admins.allows('member'), isFalse);

      expect(GroupPermissionScope.everyone.allows('owner'), isTrue);
      expect(GroupPermissionScope.everyone.allows('admin'), isTrue);
      expect(GroupPermissionScope.everyone.allows('member'), isTrue);
    });

    test('no scope permits an account with no membership row', () {
      for (final scope in GroupPermissionScope.values) {
        expect(scope.allows(null), isFalse, reason: '$scope admitted a null');
      }
    });

    test('an unrecognised role is evaluated as a plain member', () {
      for (final scope in GroupPermissionScope.values) {
        expect(scope.allows('curator'), scope.allows('member'));
      }
    });
  });
}
