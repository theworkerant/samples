defmodule BargainsWeb.EvilEyeAnimationLive do
  use Phoenix.LiveView

  def mount(_session, socket) do
    heartbeat_ms = 100

    assigns = [
      heartbeats: 0,
      heartbeat_ms: heartbeat_ms,
      blinking: false,
      next_blink: random_blink,
      random_degree1: random_degree,
      random_degree2: random_degree
    ]

    Process.send_after(self(), "heartbeat", heartbeat_ms)

    {:ok, assign(socket, assigns)}
  end

  def render(assigns) do
    Phoenix.View.render(BargainsWeb.PageView, "evil_eye_animation.html", assigns)
  end

  def handle_info("heartbeat", socket) do
    heartbeats = socket.assigns.heartbeats

    socket =
      if heartbeats > 0 && rem(heartbeats, socket.assigns.next_blink) == 0 do
        assign(socket, blinking: true, next_blink: socket.assigns.next_blink + random_blink)
      else
        assign(socket, blinking: false)
      end

    socket =
      if heartbeats > 0 && rem(heartbeats, 200) == 0 do
        assign(socket,
          random_degree1: random_degree,
          random_degree2: random_degree
        )
      else
        socket
      end

    Process.send_after(self(), "heartbeat", socket.assigns.heartbeat_ms)

    {:noreply, assign(socket, heartbeats: heartbeats + 1)}
  end

  def random_blink do
    Enum.random([3, 50, 100, 100, 100, 300, 300, 300, 300, 300, 500])
  end

  def random_degree do
    1..360 |> Stream.into([]) |> Enum.random()
  end
end
