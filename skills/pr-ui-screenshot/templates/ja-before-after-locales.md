## スクリーンショット

{{#if hasPairs}}
<!-- UIの変更がある場合は、変更前後のスクリーンショットを添付してください -->

| 旧  | 新  |
| --- | --- |
{{#each pairs}}
| {{before}} | {{after}} |
{{/each}}
{{/if}}

{{#if hasLocaleMatrix}}
<!-- 翻訳ファイルに変更がある場合は、全言語のスクリーンショットを添付してください -->

| {{#each locales}}{{this}} | {{/each}}
| {{#each locales}}--- | {{/each}}
{{#each localeRows}}
| {{#each cells}}{{this}} | {{/each}}
{{/each}}
{{/if}}
