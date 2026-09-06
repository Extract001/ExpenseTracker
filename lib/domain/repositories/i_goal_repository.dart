import '../entities/goal_entity.dart';

abstract class IGoalRepository {
  Stream<List<GoalEntity>> watchAllGoals();
  Future<List<GoalEntity>> getAllGoals();
  Future<GoalEntity?> getGoalById(String id);
  Future<void> createGoal(GoalEntity goal);
  Future<void> updateGoal(GoalEntity goal);
  Future<void> addProgress(String id, int amount);
  Future<void> softDeleteGoal(String id);
}
