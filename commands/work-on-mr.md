---
description: Work on a Drupal.org issue's merge request
args:
  - name: issue_number
    description: The Drupal.org issue number
    required: true
---

You are helping work on a Drupal.org issue and its merge request.

## Step 1: Get Issue Information

First, get the issue details using the `/do-issue-info {{issue_number}}` slash command.

## Step 2: Check for Open Merge Requests

After receiving the issue information, check if there are any open merge requests:
- If there are NO open merge requests, tell the user "No open merge requests found for issue {{issue_number}}" and STOP.
- If there are open merge requests, continue to Step 3.

## Step 3: Checkout the Merge Request

Use the following command to checkout the merge request branch locally:

```bash
php "/Users/ted.bowman/projects/drupal-scripts/do.php" mr-checkout {{issue_number}}
```

Wait for the checkout to complete successfully.

## Step 4: Understand the Issue

Based on the issue information you received:
1. Summarize the problem being solved
2. Summarize what the merge request is trying to accomplish
3. Note any important discussion points from comments
4. Identify any unresolved questions or concerns

Then, ask the user any clarifying questions you need to work on the issue, such as:
- What specifically do they want you to work on?
- Are there any failing tests to fix?
- Are there any requested changes from reviewers to address?
- Do they want you to add new functionality or fix existing issues?

## Step 5: Implement Changes

Once you have the answers you need:
1. Make the necessary changes to address the issue
2. Follow Drupal coding standards (use phpcs, phpstan)
3. Add or update tests if needed
4. Explain what you're doing as you work

## Important Notes

- Always read the issue description and comments carefully
- Pay attention to reviewer feedback in the MR
- Use TodoWrite to track tasks if the work is complex
- Run code quality checks before finishing
- Ask questions if anything is unclear

Start with Step 1 now.
