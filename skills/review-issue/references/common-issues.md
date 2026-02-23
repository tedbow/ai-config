# Common Issues in Drupal Contributions

This document catalogs common problems found in Drupal contributions to help identify them during code review.

## Coding Standards Violations

### Missing or Incorrect Docblocks
```php
// Bad: Missing parameter types and descriptions
/**
 * Process the thing.
 */
public function process($data) { }

// Good: Complete docblock
/**
 * Processes user data and updates the entity.
 *
 * @param array $data
 *   An array of user data containing 'name' and 'email' keys.
 *
 * @return \Drupal\user\UserInterface
 *   The updated user entity.
 *
 * @throws \InvalidArgumentException
 *   When required data keys are missing.
 */
public function process(array $data): UserInterface { }
```

### Incorrect Use of t() and Translation
```php
// Bad: Variable in translatable string
$this->t("Hello $name");

// Bad: Concatenation
$this->t('Hello') . ' ' . $name;

// Good: Placeholder
$this->t('Hello @name', ['@name' => $name]);
```

### Line Length and Formatting
- Lines should not exceed 80 characters where possible
- Control structure keywords should have spaces around parentheses
- Array syntax should use short array syntax (`[]` not `array()`)

## Security Vulnerabilities

### Unescaped Output
```php
// Bad: Direct output of user input
<div><?php echo $user_input; ?></div>

// Bad: Render array without #plain_text or #markup
['#markup' => $user_input]

// Good: Escaped output
<div><?php echo Html::escape($user_input); ?></div>

// Good: Plain text in render array
['#plain_text' => $user_input]
```

### SQL Injection
```php
// Bad: String concatenation in queries
$query = "SELECT * FROM {users} WHERE name = '" . $name . "'";

// Good: Query builder with conditions
$query = $this->database->select('users', 'u')
  ->fields('u')
  ->condition('name', $name)
  ->execute();
```

### Missing Access Checks
```php
// Bad: No access check
public function viewEntity($entity_id) {
  $entity = $this->entityTypeManager->getStorage('node')->load($entity_id);
  return $entity->toArray();
}

// Good: Access check
public function viewEntity($entity_id) {
  $entity = $this->entityTypeManager->getStorage('node')->load($entity_id);
  if (!$entity->access('view')) {
    throw new AccessDeniedHttpException();
  }
  return $entity->toArray();
}
```

## Performance Issues

### N+1 Query Problem
```php
// Bad: Loading entities in a loop
foreach ($node_ids as $nid) {
  $node = Node::load($nid);
  // Process node
}

// Good: Bulk load
$nodes = Node::loadMultiple($node_ids);
foreach ($nodes as $node) {
  // Process node
}
```

### Missing Cache Metadata
```php
// Bad: No cache metadata
return [
  '#markup' => $this->t('Current user: @name', ['@name' => $user->getDisplayName()]),
];

// Good: Proper cache contexts
return [
  '#markup' => $this->t('Current user: @name', ['@name' => $user->getDisplayName()]),
  '#cache' => [
    'contexts' => ['user'],
  ],
];
```

### Loading All Entities Without Pagination
```php
// Bad: Load all nodes
$nodes = $this->entityTypeManager->getStorage('node')->loadByProperties(['type' => 'article']);

// Good: Use entity query with range
$query = $this->entityTypeManager->getStorage('node')->getQuery()
  ->condition('type', 'article')
  ->range(0, 50)
  ->accessCheck(TRUE);
$nids = $query->execute();
```

## API Misuse

### Static Service Container Calls
```php
// Bad: Static calls in service methods
class MyService {
  public function doSomething() {
    $config = \Drupal::config('mymodule.settings');
  }
}

// Good: Dependency injection
class MyService {
  public function __construct(
    protected ConfigFactoryInterface $configFactory,
  ) {}

  public function doSomething() {
    $config = $this->configFactory->get('mymodule.settings');
  }
}
```

### Direct Database Access for Entities
```php
// Bad: Direct DB query
$result = \Drupal::database()->query("SELECT nid FROM {node} WHERE type = 'article'");

// Good: Entity query
$query = \Drupal::entityQuery('node')
  ->condition('type', 'article')
  ->accessCheck(TRUE);
$nids = $query->execute();
```

### Incorrect Hook Implementation
```php
// Bad: Missing hook name pattern
function mymodule_form_alter(&$form, $form_state, $form_id) { }

// Good: Correct hook name
function mymodule_form_alter(&$form, FormStateInterface $form_state, $form_id) { }
```

## Testing Issues

### Missing Access Checks in Tests
```php
// Bad: Not testing access
public function testEntityView() {
  $entity = $this->createEntity();
  $this->drupalGet($entity->toUrl());
  $this->assertSession()->statusCodeEquals(200);
}

// Good: Test access for different users
public function testEntityAccess() {
  $entity = $this->createEntity();

  // Anonymous user should not access
  $this->drupalGet($entity->toUrl());
  $this->assertSession()->statusCodeEquals(403);

  // Authenticated user with permission should access
  $this->drupalLogin($this->createUser(['view entity']));
  $this->drupalGet($entity->toUrl());
  $this->assertSession()->statusCodeEquals(200);
}
```

### Not Cleaning Up Test Data
```php
// Bad: No cleanup
public function testSomething() {
  $node = Node::create(['type' => 'article', 'title' => 'Test']);
  $node->save();
  // Test logic
}

// Good: Use test entity creation or cleanup
public function testSomething() {
  $node = $this->createNode(['type' => 'article', 'title' => 'Test']);
  // Test logic - automatically cleaned up by test framework
}
```

### Tests Without Assertions
```php
// Bad: No assertions
public function testProcess() {
  $this->myService->process(['data' => 'test']);
}

// Good: Assert expected behavior
public function testProcess() {
  $result = $this->myService->process(['data' => 'test']);
  $this->assertEquals('expected', $result);
  $this->assertTrue($result->isProcessed());
}
```

## Configuration Issues

### Missing Configuration Schema
```yaml
# Bad: No schema file for mymodule.settings.yml
# /config/install/mymodule.settings.yml exists
# but /config/schema/mymodule.schema.yml is missing

# Good: Schema file exists
# config/schema/mymodule.schema.yml
mymodule.settings:
  type: config_object
  label: 'My Module settings'
  mapping:
    api_key:
      type: string
      label: 'API Key'
```

### Hardcoded Configuration
```php
// Bad: Hardcoded values
public function sendEmail() {
  $to = 'admin@example.com';
  // ...
}

// Good: Configuration
public function sendEmail() {
  $config = $this->configFactory->get('mymodule.settings');
  $to = $config->get('admin_email');
  // ...
}
```

## Database Schema Issues

### Missing Indexes
```php
// Bad: No index on frequently queried field
$schema['mytable'] = [
  'fields' => [
    'id' => ['type' => 'serial'],
    'user_id' => ['type' => 'int'],
    'status' => ['type' => 'varchar', 'length' => 32],
  ],
  'primary key' => ['id'],
];

// Good: Index on queried fields
$schema['mytable'] = [
  'fields' => [
    'id' => ['type' => 'serial'],
    'user_id' => ['type' => 'int'],
    'status' => ['type' => 'varchar', 'length' => 32],
  ],
  'primary key' => ['id'],
  'indexes' => [
    'user_status' => ['user_id', 'status'],
  ],
];
```

### Missing or Incorrect Update Hooks
```php
// Bad: Schema change without update hook
// Just modified .install file schema definition

// Good: Update hook for schema change
/**
 * Add status field to mytable.
 */
function mymodule_update_8001() {
  $schema = Database::getConnection()->schema();
  $schema->addField('mytable', 'status', [
    'type' => 'varchar',
    'length' => 32,
    'not null' => TRUE,
    'default' => 'active',
  ]);
}
```

## Dependency Injection Issues

### Missing Interface Type Hints
```php
// Bad: No type hint
public function __construct($entity_type_manager) {
  $this->entityTypeManager = $entity_type_manager;
}

// Good: Interface type hint
public function __construct(EntityTypeManagerInterface $entity_type_manager) {
  $this->entityTypeManager = $entity_type_manager;
}
```

### Not Using Constructor Property Promotion (PHP 8+)
```php
// Verbose: Old style
public function __construct(EntityTypeManagerInterface $entity_type_manager) {
  $this->entityTypeManager = $entity_type_manager;
}

// Good: Constructor property promotion (Drupal 10.1+)
public function __construct(
  protected EntityTypeManagerInterface $entityTypeManager,
) {}
```

## Form API Issues

### Not Using Form State for Storage
```php
// Bad: Using class properties
class MyForm extends FormBase {
  private $tempData;

  public function submitForm(array &$form, FormStateInterface $form_state) {
    $this->tempData = $form_state->getValue('data');
  }
}

// Good: Using form state storage
public function submitForm(array &$form, FormStateInterface $form_state) {
  $form_state->set('temp_data', $form_state->getValue('data'));
  $temp_data = $form_state->get('temp_data');
}
```

### Missing AJAX Callbacks
```php
// Bad: AJAX element without callback
$form['ajax_field'] = [
  '#type' => 'textfield',
  '#ajax' => [
    'wrapper' => 'result-wrapper',
  ],
];

// Good: AJAX element with callback
$form['ajax_field'] = [
  '#type' => 'textfield',
  '#ajax' => [
    'callback' => '::ajaxCallback',
    'wrapper' => 'result-wrapper',
    'event' => 'change',
  ],
];
```

## Service Definition Issues

### Missing Service Tags
```yaml
# Bad: Service that should implement event subscriber but missing tag
services:
  mymodule.my_subscriber:
    class: Drupal\mymodule\EventSubscriber\MySubscriber

# Good: Proper event subscriber with tag
services:
  mymodule.my_subscriber:
    class: Drupal\mymodule\EventSubscriber\MySubscriber
    tags:
      - { name: event_subscriber }
```

### Public Methods That Should Be Private
```php
// Bad: Helper method is public
class MyService {
  public function doSomething() {
    return $this->helperMethod();
  }

  public function helperMethod() {
    // Only used internally
  }
}

// Good: Helper method is private
class MyService {
  public function doSomething() {
    return $this->helperMethod();
  }

  private function helperMethod() {
    // Only used internally
  }
}
```

## Best Practice Checklist

When reviewing, watch for:

- [ ] Are all user inputs validated and sanitized?
- [ ] Are all database queries using proper APIs?
- [ ] Are all services properly injected?
- [ ] Are all configuration values in config files, not hardcoded?
- [ ] Are all user-facing strings translatable?
- [ ] Are all entities loaded using entity API, not direct queries?
- [ ] Are all access checks present?
- [ ] Are all cache metadata tags, contexts, and max-age set?
- [ ] Are all tests covering edge cases?
- [ ] Are all schema changes accompanied by update hooks?
- [ ] Are all new configuration entities accompanied by schema definitions?
- [ ] Are all deprecated APIs avoided?
- [ ] Are all performance-critical operations optimized?
