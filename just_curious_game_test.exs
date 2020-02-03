defmodule JustCurious.GameTest do
  use JustCurious.BotCase

  setup do
    no_chain_questions()
    {:ok, %{game: standard_new_game()}}
  end

  test "New game setup properly", %{game: game} do
    assert game.name == "Durazno"
    assert game.channel == "durazno"
    assert Enum.sort(participants(game)) == Enum.sort([@user1, @user2, @user3, @user4])
    assert spectators(game) == [@user4]
    assert Enum.member?(smembers("team:#{@team}:games"), game.channel)
    assert hget("team:#{@team}:game:#{game}:participant:#{@user1}", "pseudonym") == "Larry"
  end

  test "Game config attributes exist", %{game: game} do
    assert is_integer(game.start_timeout)
    assert game.start_timeout == 1800_000_000 # microseconds
    assert is_integer(game.start_reminder)
    assert is_integer(game.submitted_timeout)
    assert is_integer(game.submitted_reminder)
    assert is_integer(game.nominated_timeout)
    assert is_integer(game.nominated_reminder)
    assert is_integer(game.answered_timeout)
    assert is_integer(game.answered_reminder)
    # assert is_integer(game.failure_extension)
  end

  test "Defaults to nil round", %{game: game}, do: assert JustCurious.Game.get_round(game) == nil
  test "Defaults to 'new' state", %{game: game}, do: assert JustCurious.Game.get_state(game) == :new

  test "Pseudonyms increment properly", %{game: game} do
    another_game = standard_new_game()
    assert JustCurious.Game.get_pseudonym(game, @user1) != JustCurious.Game.get_pseudonym(another_game, @user1)
  end

  test "Transitioning without an active game doesn't work" do
    direct_message("transition submitted") |> assert_matching_reply(:transition_error)
  end

  test "Transition errors sent to user, not game channel" do
    direct_message("transition submitted") |> assert_matching_reply(:transition_error)
  end

  test "starting the game moves joined invites to player status", %{game: game} do
    assert JustCurious.Game.joins(game) == [@user1, @user2, @user3]
    assert JustCurious.Game.players(game) == []
    start_game(game)
    assert JustCurious.Game.players(game) == [@user1, @user2, @user3]
  end

  test "transition -> 'submitting' when at least 3 players are present" do
    game = JustCurious.Game.create(@team, %{joins: [@user1, @user2], spectators: [@user4]})
    message = direct_message("transition start")
    direct_message("2")
    assert_matching_reply(message, :transition_error)

    JustCurious.Game.add_participant(game, @user3, :join)
    message = direct_message("transition start")
    direct_message("2")
    assert_matching_reply(message, :transition_start)
  end

  test "transition -> 'answering' when at least one nominated submission exists", %{game: game} do
    start_game(game)
    direct_message("transition nominated") |> assert_matching_reply(:transition_error)

    zincrby("team:#{game.team}:game:#{game}:submissions", 1, "question-o-matic-0")

    direct_message("transition nominated") |> assert_matching_reply(:transition_answering)
    assert JustCurious.Game.get_round(game) == :answering
  end

  test "transition -> 'answering' sends message with winning submission", %{game: game} do
    start_game(game, :nominated) |> assert_matching_reply(:transition_answering)
  end

  test "transition -> 'start' when already started", %{game: game} do
    start_game(game)
    direct_message("transition start") |> assert_matching_reply(:transition_error)
    assert JustCurious.Game.get_round(game) == :nominating
  end

  test "transition -> 'complete' when at least three answers exists", %{game: game} do
    start_game(game, :nominated)
    direct_message("transition answered") |> assert_matching_reply(:transition_error)

    hset("team:#{game.team}:game:#{game}:participant:#{@user1}", "answer_0", "Some answer.")
    hset("team:#{game.team}:game:#{game}:participant:#{@user2}", "answer_0", "Some answer.")
    hset("team:#{game.team}:game:#{game}:participant:#{@user3}", "answer_0", "Some answer.")

    direct_message("transition answered") |> assert_matching_reply(:transition_answered)
    assert JustCurious.Game.get_round(game) == :complete
  end
end
