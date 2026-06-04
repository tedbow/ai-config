---
name: Work on Merge Request
description: This skill should be used when the user asks to "work on an MR", "work on a merge request", "help with a drupal issue", "help with a gitlab issue", or wants to make changes to code for a Drupal.org or GitLab issue's merge request.
version: 2.0.0
args:
  - name: issue_ref
    description: The Drupal.org issue number or full GitLab work_items URL (e.g. https://git.drupalcode.org/project/canvas/-/work_items/3591459)
    required: true
---

# Work on Merge Request Skill

You are helping work on a Drupal.org or GitLab issue and its merge request by checking out the code, understanding the context, and implementing necessary changes.

## Workflow

### Step 1: Detect Issue Type and Get Issue Information

**Detect issue type from args:**

**GitLab issue** — input matches `https://<host>/<namespace>/<project>/-/work_items/<iid>`
- Extract: `host`, `project_path`, `issue_iid`

**Drupal.org issue** — plain number or `https://drupal.org/...` URL

Get full issue details using the "Get Issue Information" skill (do-issue-info), passing the issue reference.

Wait for the full issue information to be retrieved before proceeding.

### Step 2: Check for Open Merge Requests

After receiving the issue information, check if there are any open merge requests:

**If there are NO open merge requests:**
- Tell the user there are no open merge requests
- Provide the issue URL
- STOP - do not proceed to further steps

**If there are open merge requests:**
- Note the MR IID (for GitLab path) or proceed normally (Drupal.org path)
- Continue to Step 3

### Step 3: Checkout the Merge Request

#### GitLab path

From within the project repo directory:
```bash
GITLAB_HOST={{host}} glab mr checkout {{mr_iid}}
```

#### Drupal.org path

```bash
do.php mr-checkout {{issue_number}}
```

**Wait for the checkout to complete successfully** before proceeding.

**Handle checkout errors:**
- If the command fails, report the error to the user
- Check if the repository path is correct
- Verify the merge request exists and is accessible

### Step 4: Understand the Issue

Based on the issue information you received, provide a comprehensive understanding:

1. **Summarize the problem being solved**
   - What bug or feature is being addressed?
   - What is the root cause or motivation?

2. **Summarize what the merge request is trying to accomplish**
   - What changes have been made?
   - What approach was taken?

3. **Note any important discussion points from comments**
   - Key decisions made
   - Alternative approaches considered
   - Reviewer feedback

4. **Identify any unresolved questions or concerns**
   - Outstanding issues from discussion
   - Failing tests
   - Requested changes not yet implemented

**Then, ask the user clarifying questions:**
- What specifically do they want you to work on?
- Are there any failing tests to fix?
- Are there any requested changes from reviewers to address?
- Do they want you to add new functionality or fix existing issues?
- Is there a specific aspect of the code they want help with?

### Step 5: Implement Changes

Once you have the answers you need:

1. **Make the necessary changes** to address the issue
   - Follow the user's specific requests
   - Address reviewer feedback if that's the goal
   - Fix failing tests if identified

2. **Follow Drupal coding standards**
   - Use phpcs (PHP CodeSniffer) to check code style
   - Use phpstan for static analysis
   - Ensure code follows Drupal best practices

3. **Add or update tests if needed**
   - Write PHPUnit tests for new functionality
   - Update existing tests if behavior changes
   - Ensure test coverage is adequate

4. **Explain what you're doing as you work**
   - Describe each change and why it's needed
   - Note any tradeoffs or design decisions
   - Keep the user informed of progress

5. **Run code quality checks before finishing**
   - Execute phpcs to verify coding standards
   - Run phpstan for static analysis
   - Run relevant tests to verify functionality

## Important Notes

- **Always read the issue description and comments carefully** - context is crucial
- **Pay attention to reviewer feedback in the MR** - address concerns raised
- **Use TodoWrite to track tasks if the work is complex** - break down large changes
- **Run code quality checks before finishing** - ensure standards compliance
- **Ask questions if anything is unclear** - don't make assumptions

## Error Handling

- **Issue not found**: Verify issue number/URL is correct
- **No open MRs**: Inform user and provide issue URL, then stop
- **Checkout fails**: Report error, check repository and permissions
- **Code quality checks fail**: Fix issues before completing the work

## Tips

- Review the entire issue thread before making changes
- Look for patterns in reviewer feedback across multiple comments
- Consider backwards compatibility when making API changes
- Write clear commit messages that reference the issue number
- Test your changes in the context of the larger system
- Document complex logic with inline comments
