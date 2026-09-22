<script lang="ts">
  import { supabase } from "$lib/supabaseClient";

  // Join a room/topic. Can be anything except for 'realtime'.
  const myChannel = supabase.channel("test-channel");

  // Function to log any messages we receive
  function messageReceived(payload) {
    console.log(payload);
  }

  // Subscribe to the Channel
  myChannel.on("broadcast", { event: "*" }, (payload) => messageReceived(payload)).subscribe();

  /**
   * Sending a message before subscribing will use HTTP
   */
  myChannel
    .send({
      type: "broadcast",
      event: "shout",
      payload: { message: "Hi" },
    })
    .then((resp) => console.log(resp));

  /**
   * Sending a message after subscribing will use WebSockets
   */
  myChannel.subscribe((status) => {
    if (status !== "SUBSCRIBED") {
      return null;
    }

    myChannel.send({
      type: "broadcast",
      event: "shout",
      payload: { message: "Hi" },
    });
  });

  /**
   * The payload can be binary (ArrayBuffer / ArrayBufferView) from supabase-js 2.91.0.
   * Receivers on older SDK versions will not get the message.
   */
  myChannel.send({
    type: "broadcast",
    event: "cursor-pos",
    payload: new Uint8Array([1, 2, 3]).buffer,
  });
</script>
