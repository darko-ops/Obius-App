Analyze the following note sections and identify recurring entities (people, places, projects, topics, lists) that the user references repeatedly or that would benefit from being a synced Loop (a content block that stays consistent across pages).

Return a JSON array of objects with: "name" (display name), "handleName" (lowercase, underscores, 2-50 chars), "reason" (1 sentence why), "sectionId" (which section contains it).

Only suggest entities that genuinely recur or would benefit from syncing. Max 3 suggestions.
Return [] if nothing qualifies. Return ONLY the JSON array, no other text.