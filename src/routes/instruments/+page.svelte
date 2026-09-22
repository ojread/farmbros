<script>
  let { data } = $props();
</script>

{#if data.error}
  <p>Error loading instruments: {data.error}</p>
{:else}
  <ul>
    {#each data.instruments as instrument}
      <li>{instrument.name}</li>
    {/each}
  </ul>
{/if}
