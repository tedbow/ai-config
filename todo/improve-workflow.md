# Goal: Improve my developer workflow with AI agents and/or skills.

I want to be able start my work for that day with one command to triage all tickets and also check drupal canvas issue queue.
I want to  reduce the work I have to do but I should be kept in the loop and be the decsion maker.
For triage I want to favor predictably. For instance if I there were scripts that got the info from jira and gitlab and then agents would got through the output, would that be more stable and save tokens?

## Current Workflow
1. `/agents/daily-triage/AGENT.md` is what I use for triaging work. It runs once per day, and writes a triage folder with a `triage.md` table of tickets and their assessments. It also writes a per-ticket work log for each ticket in the table.
2. I have 2 version of claude I use config at `~/.claude` and `~/.claude-mine`. The former is the default, but I have a symlink to the latter for my personal config.
 - `~/.claude-mine` is my personal max subscription. I use this for any open source work.I cannot use it for proprietary work or cannot let it access my jira etc. It has access to better models and has more tokens etc.
 - `~/.claude` is my work's via a gateway. It can access anything open source or proprietary, but it is not my personal max subscription.
3. I have various types of work
    - jira tickets that point to github for proprietary work. 100% is https://github.com/acquia/haas-drupal maybe other repos in the future.(🤖To agent if you are from `~/.claude-mine` don't try to access this)
    - jira tickets that point to gitlab for open source work. 95% is Drupal Canvas work, but some is other open source work.
    - Drupal canvas gitlab issues that are not in jira.
4. For local development work I use 2 types of setups:
   1. Drupal canvas and other drupal open source work: setup via Users/ted.bowman/projects/drupal-scripts/src/Command/SiteSetup.php. by do.php site:setup canvas-[ISSUE_NUMBER] or similar
   2. Proprietary work: setup via Users/ted.bowman/projects/haas-drupal-2 which is ddev site. I have multiple copies of this but often just use the 1.
   The reason I am make duplicate sites rather than just using 1 directory and switch between branches or using git works is that I have multiple tickets that are in progress and I want to be able to switch between them without losing work. I also want to be able to run multiple sites at the same time for testing. also I think functional tests do not work with worktrees

I use https://herdr.dev/ or my main terminal. I will 1 "space" for each site I am working on. might have multiple tabs running multiple agents.


## Current Workflow Challenges

1. `/agents/daily-triage/AGENT.md` has some problems:
   - does look not for drupal.org git lab issue that I am assigned or mentioned in that do not have jira ticket.
   - does not let me artibutrary pick issue in jira or gitlab that I want to monitor or otherwise have an interest in.
   - when ask the agent to work on a ticket I have to set-up the site manually.

## Additions

would like to be able for the triage agent to spin up other agents to work on each ticket or the ones I ask it to with minimal involvement from me. I would like the agents to be able interact with spun agents. Not sure if that means they need to be separate terminal.

Probably the agent running triage needs to use ~/.claude because it can access everything. But it should be able to spin up agents that use ~/.claude-mine for open source work. The spun agents should be able to access the same files as the triage agent.
There should triage on general Canvas issues but that should be run by ~/.claude-mine. Not sure if the main triage agent should spin that up and access the results
