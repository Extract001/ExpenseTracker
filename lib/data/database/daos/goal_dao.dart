import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/savings_goals_table.dart';

part 'goal_dao.g.dart';

@DriftAccessor(tables: [SavingsGoalsTable])
class GoalDao extends DatabaseAccessor<AppDatabase> with _$GoalDaoMixin {
  GoalDao(super.db);

  Stream<List<SavingsGoalData>> watchAllGoals(String userId) {
    return (select(savingsGoalsTable)
          ..where((g) => g.userId.equals(userId) & g.deletedAtUtc.isNull())
          ..orderBy([(g) => OrderingTerm.asc(g.targetDateUtc)]))
        .watch();
  }

  Future<List<SavingsGoalData>> getAllGoals(String userId) {
    return (select(savingsGoalsTable)
          ..where((g) => g.userId.equals(userId) & g.deletedAtUtc.isNull())
          ..orderBy([(g) => OrderingTerm.asc(g.targetDateUtc)]))
        .get();
  }

  Future<SavingsGoalData?> getGoalById(String id) {
    return (select(
      savingsGoalsTable,
    )..where((g) => g.id.equals(id))).getSingleOrNull();
  }

  Future<int> insertGoal(SavingsGoalsTableCompanion entry) {
    return into(savingsGoalsTable).insert(entry);
  }

  Future<bool> updateGoal(SavingsGoalsTableCompanion entry) {
    return update(savingsGoalsTable).replace(entry);
  }

  Future<int> updateGoalProgress({
    required String id,
    required int newCurrentAmountMinor,
    required DateTime updatedAtUtc,
    String syncStatus = 'pendingUpdate',
  }) {
    return (update(savingsGoalsTable)..where((g) => g.id.equals(id))).write(
      SavingsGoalsTableCompanion(
        currentAmountMinor: Value(newCurrentAmountMinor),
        updatedAtUtc: Value(updatedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }

  Future<int> softDeleteGoal({
    required String id,
    required DateTime deletedAtUtc,
    String syncStatus = 'pendingDelete',
  }) {
    return (update(savingsGoalsTable)..where((g) => g.id.equals(id))).write(
      SavingsGoalsTableCompanion(
        deletedAtUtc: Value(deletedAtUtc),
        updatedAtUtc: Value(deletedAtUtc),
        syncStatus: Value(syncStatus),
      ),
    );
  }
}
