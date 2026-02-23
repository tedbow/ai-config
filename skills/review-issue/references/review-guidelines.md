# Drupal Code Review Guidelines

This document provides best practices and guidelines for reviewing Drupal contributions.

## High-Level Review Checklist

### Architecture & Design
- [ ] Does the approach align with Drupal best practices and patterns?
- [ ] Are appropriate APIs and services used?
- [ ] Is the code leveraging existing Drupal subsystems properly?
- [ ] Are there any circular dependencies or tight coupling?
- [ ] Does the design support extensibility and flexibility?
- [ ] Are there backwards compatibility considerations?

### Code Quality
- [ ] Does the code follow Drupal coding standards?
- [ ] Are functions and methods appropriately sized and focused?
- [ ] Is the code maintainable and readable?
- [ ] Are variable and function names descriptive and clear?
- [ ] Is there appropriate error handling?
- [ ] Are there any potential performance issues?

### Security
- [ ] Are user inputs properly validated and sanitized?
- [ ] Are SQL queries using proper query builders or entity API?
- [ ] Are file operations secure?
- [ ] Is access control properly implemented?
- [ ] Are secrets/credentials handled securely?
- [ ] Check for XSS, SQL injection, CSRF vulnerabilities

### Testing
- [ ] Are there unit tests for business logic?
- [ ] Are there functional/integration tests for user-facing features?
- [ ] Do tests cover edge cases and error conditions?
- [ ] Are existing tests updated if behavior changes?
- [ ] Do tests follow Drupal testing best practices?
- [ ] Is test coverage adequate for the changes?

### Documentation
- [ ] Are docblocks present and accurate?
- [ ] Are complex algorithms or patterns explained?
- [ ] Is user-facing documentation updated (README, help text)?
- [ ] Are API changes documented in change records?
- [ ] Are upgrade paths documented if needed?

### Database & Schema
- [ ] Are schema changes properly implemented with update hooks?
- [ ] Are indexes appropriate for query patterns?
- [ ] Are data migrations tested and reversible where possible?
- [ ] Do schema changes support rollback?

### Configuration Management
- [ ] Are configuration entities properly defined?
- [ ] Are configuration schemas provided?
- [ ] Are default configurations sensible?
- [ ] Are configuration imports/exports handled correctly?

### API & Backwards Compatibility
- [ ] Are API changes backwards compatible?
- [ ] Are deprecations properly marked and documented?
- [ ] Is there an upgrade path for breaking changes?
- [ ] Are change records needed?
- [ ] Do API signatures make sense?

### Performance
- [ ] Are database queries optimized?
- [ ] Is caching implemented where appropriate?
- [ ] Are expensive operations deferred or queued?
- [ ] Is the render array cacheable metadata correct?
- [ ] Are there N+1 query issues?

### Accessibility (if UI changes)
- [ ] Are forms accessible (labels, ARIA attributes)?
- [ ] Is keyboard navigation supported?
- [ ] Is color contrast sufficient?
- [ ] Are screen reader announcements appropriate?

### Internationalization
- [ ] Are all user-facing strings wrapped in translation functions?
- [ ] Is date/time formatting locale-aware?
- [ ] Are plurals handled correctly?
- [ ] Is RTL layout supported if needed?

## Drupal-Specific Patterns to Check

### Service Container Usage
```php
// Good: Dependency injection
class MyService {
  public function __construct(
    protected EntityTypeManagerInterface $entityTypeManager,
  ) {}
}

// Avoid: Direct service container calls in business logic
\Drupal::entityTypeManager();
```

### Entity API Usage
```php
// Good: Use entity type manager
$storage = $this->entityTypeManager->getStorage('node');
$nodes = $storage->loadByProperties(['type' => 'article']);

// Avoid: Direct database queries for entities
db_query("SELECT * FROM node WHERE type = 'article'");
```

### Render Arrays
```php
// Good: Proper cacheable metadata
$build = [
  '#markup' => $this->t('Hello'),
  '#cache' => [
    'contexts' => ['user'],
    'tags' => $entity->getCacheTags(),
    'max-age' => Cache::PERMANENT,
  ],
];
```

### Form API
```php
// Good: Form validation and submission handlers
public function validateForm(array &$form, FormStateInterface $form_state) {
  if (!valid($form_state->getValue('field'))) {
    $form_state->setErrorByName('field', $this->t('Invalid value'));
  }
}
```

## Common Issues to Flag

### Security Issues
- Direct use of `$_GET`, `$_POST`, `$_REQUEST` without validation
- Unescaped output in templates or render arrays
- SQL queries with string concatenation
- Missing access checks on routes or operations
- Unsafe file operations

### Performance Issues
- Loading all entities of a type without pagination
- Queries inside loops (N+1 problem)
- Missing or incorrect cache contexts/tags/max-age
- Expensive operations in request handlers

### API Misuse
- Using deprecated APIs
- Bypassing proper APIs (direct DB access for entities)
- Not using typed data or plugin APIs where appropriate
- Incorrect use of static caching

### Testing Gaps
- No tests for new functionality
- Tests that don't actually assert behavior
- Missing edge case coverage
- Tests dependent on specific test data ordering

## Review Communication Tips

### Be Constructive
- Frame feedback as suggestions, not demands
- Explain the "why" behind recommendations
- Acknowledge good practices used
- Offer alternatives when pointing out issues

### Be Specific
- Reference specific files and line numbers
- Provide code examples for suggested changes
- Link to Drupal API documentation or change records
- Cite coding standards when applicable

### Prioritize Issues
- Distinguish between critical issues and nice-to-haves
- Flag security and data loss issues immediately
- Note architectural concerns that may need wider discussion
- Separate coding standard nitpicks from functional concerns

### Example Feedback Format
```
**Concern**: Potential SQL injection vulnerability (Critical)
**Location**: src/MyService.php:45
**Issue**: Direct string concatenation in SQL query
**Suggestion**: Use query builder or entity API instead

// Current
$query = "SELECT * FROM users WHERE name = '$name'";

// Suggested
$query = $this->database->select('users', 'u')
  ->fields('u')
  ->condition('name', $name)
  ->execute();
```

## When to Involve Others

- **Core maintainers**: API changes, core subsystem modifications
- **Security team**: Potential security vulnerabilities
- **Framework managers**: Architectural decisions, major patterns
- **Component maintainers**: Changes to specific subsystems
- **Release managers**: Critical bugs, release blocking issues

## References

- [Drupal Coding Standards](https://www.drupal.org/docs/develop/standards)
- [Drupal API Documentation](https://api.drupal.org/)
- [Security Best Practices](https://www.drupal.org/docs/security-in-drupal)
- [Code Review Process](https://www.drupal.org/core-mentoring/mentored-contribution-process)
