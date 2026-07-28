## Screenshots

{{#if hasPairs}}
| Before | After |
| --- | --- |
{{#each pairs}}
| {{before}} | {{after}} |
{{/each}}
{{/if}}

{{#if hasLocaleMatrix}}
| {{#each locales}}{{this}} | {{/each}}
| {{#each locales}}--- | {{/each}}
{{#each localeRows}}
| {{#each cells}}{{this}} | {{/each}}
{{/each}}
{{/if}}
