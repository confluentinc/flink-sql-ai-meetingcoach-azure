# InsightCRM Demo Knowledge Base

To re-generate the JSON files from the sample knowledge base markdown files: from the root of the repo, run the following command:
```bash
cd sample-data &&
python process_md_to_json.py --input "/knowledge_base_markdown" --output "/knowledge_base_json" --recursive
```


## Project Overview
This knowledge base contains simulated sales enablement documents for a fictional B2B SaaS product called InsightCRM - an AI-enhanced CRM platform with contextual intelligence capabilities. The standout feature is "SalesCoach" which provides real-time, contextual insights during sales conversations.

## Purpose
These documents will be used in a demo showcasing how LLMs can combine knowledge documents with real-time meeting transcripts to provide sales representatives with the perfect context at the perfect moment. The system analyzes the conversation and provides contextually relevant information only when it would be most impactful.

## Document Categories
1. **Competitive Intelligence Profiles** - Analysis of key competitors
2. **Industry Verticals Guides** - Sector-specific information
3. **Buyer Persona Dossiers** - Profiles of decision-makers
4. **Value Proposition Frameworks** - Structured messaging for benefits
5. **Objection Response Playbooks** - Strategies for addressing concerns
6. **ROI Calculation Templates** - Models showing financial impact
7. **Technical Capability Briefs** - Explanations of core technologies
8. **Implementation Roadmaps** - Guides to the onboarding journey
9. **Customer Success Stories** - Case studies by industry
10. **Integration Ecosystem Overviews** - How the solution works with other technologies

## Demo Concept
The demo will show how the system:
- Listens to a live sales conversation
- Only interjects when truly valuable information can be provided
- References specific source documents for credibility
- Provides concise, actionable insights
- Helps sales reps navigate objections, competitive comparisons, and technical questions

## Sample Triggers for System Response
- Prospect mentions a competitor
- Clear sales objection is raised
- Prospect expresses specific concerns about implementation
- Technical questions that require precise information
- Discussion of decision criteria
- Conversation reaching critical milestone

## Note on Document Creation
Documents are intentionally concise and focused on information that would be most contextually advantageous during a sales conversation. They're designed to provide "aha" moments when the system provides the perfect context for responding to prospect statements.
