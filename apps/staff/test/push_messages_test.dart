import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_staff/app/push_messages.dart';
import 'package:sparkling_staff/app/router.dart';

void main() {
  group('staff push payload routing', () {
    test('task and work-order pushes open the checklist', () {
      expect(
        routeForStaffPush({
          'type': 'task',
          'task_id': 't1',
          'work_order_id': 'wo1',
          'template': 'task_verify_requested',
        }),
        Routes.checklist('wo1'),
      );
      expect(
        routeForStaffPush({'type': 'work_order', 'work_order_id': 'wo2'}),
        Routes.checklist('wo2'),
      );
      expect(routeForStaffPush({'type': 'task'}), Routes.tasks);
      expect(routeForStaffPush({'type': 'inventory'}), Routes.inventory);
      expect(routeForStaffPush({'type': 'quotation'}), isNull);
      expect(routeForStaffPush(const {}), isNull);
    });

    test('task pushes refresh the task streams', () {
      expect(tableForStaffPush({'type': 'task'}), 'tasks');
      expect(tableForStaffPush({'type': 'work_order'}), 'tasks');
      expect(tableForStaffPush({'type': 'inventory'}), 'inventory_items');
      expect(tableForStaffPush({'type': 'booking'}), isNull);
    });
  });
}
