# orchestrator — ru

## error_no_task_id
Укажи номер задачи, например `запусти 026` / `/task-run 026`.

## error_task_not_found
Задача `{task_id}` не найдена в `Tasks/`.

## fallback_profile_question
Какой профиль? (1) FEATURE (2) BUG (3) REFACTOR (4) TEST (5) REVIEW (6) EPIC

## confirm_dispatch
Профиль: `{profile}`, режим: `{mode}`, стек: `{stack}`, старт: `{start_stage}`. Верно?

## error_research_required
Стадия `{stage}` требует `Research.md`. Запустите Research или используйте `--skip-research`.

## error_redo_no_artifact
Нечего переделывать — артефакта `{stage}` нет. Используйте `run --from {stage}`.

## stage_done_prompt
`{stage}` готова. Перейти к следующей? [Yes / Edit / No]

## auq_stage_recovery_question
Стадия `{invalid_stage}` не входит в профиль `{profile}`. Допустимы: {profile_stages_list}. Выберите одну:

## auq_stage_override_question
Выберите другую стартовую стадию для профиля `{profile}`:

## auq_stage_recovery_recommended_suffix
(Рекомендуется)

## auq_confirm_dispatch_pick_stage
Нет, выбрать другую стадию

## error_stage_not_in_profile
`{invalid_stage}` — недопустимая стадия профиля `{profile}`. Допустимы: {profile_stages_list}.

## confirm_dispatch_yes
Да

## confirm_dispatch_cancel
Отмена

## auq_axis_ui_question
Какой UI-фреймворк использует эта задача?

## auq_axis_async_question
Какой async-подход использует эта задача?

## auq_axis_di_question
Какой подход Dependency Injection использует эта задача?

## auq_axis_arch_question
Какую архитектуру использует эта задача?

## auq_axis_platform_question
Какую целевую платформу использует эта задача?

## auq_axis_tests_question
Какой тестовый фреймворк использует эта задача?
