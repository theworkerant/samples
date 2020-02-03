defmodule RobotSimulator do
  @directions [:north, :east, :south, :west]

  def create(direction \\ :north, position \\ {0,0})
  def create(_dir, position) when not is_tuple(position) or tuple_size(position) != 2, do: {:error, "invalid position"}
  def create(_dir, {x,y}) when not is_number(x) or not is_number(y), do: {:error, "invalid position"}
  def create(direction, _pos) when direction not in @directions, do: {:error, "invalid direction"}
  def create(direction, position), do: {direction, position}

  def direction({direction, _position}), do: direction
  def position({_direction, position}), do: position

  def simulate(robot, ""), do: robot
  def simulate({direction, position}, "L" <> instructions), do: {turn_left(direction), position} |> simulate(instructions)
  def simulate({direction, position}, "R" <> instructions), do: {turn_right(direction), position} |> simulate(instructions)
  def simulate({:north, {x,y}}, "A" <> instructions), do: {:north, {x,y+1}} |> simulate(instructions)
  def simulate({:south, {x,y}}, "A" <> instructions), do: {:south, {x,y-1}} |> simulate(instructions)
  def simulate({:east, {x,y}}, "A" <> instructions), do: {:east, {x+1,y}} |> simulate(instructions)
  def simulate({:west, {x,y}}, "A" <> instructions), do: {:west, {x-1,y}} |> simulate(instructions)
  def simulate(_robot, _instructions), do: {:error, "invalid instruction"}

  defp turn_left(current) do
    index = Enum.find_index(@directions, & &1 == current)
    Enum.at(@directions, index-1)
  end

  defp turn_right(current) do
    index = Enum.find_index(@directions, & &1 == current)
    if index == 3 do
      Enum.at(@directions, 0)
    else
      Enum.at(@directions, index+1)
    end
  end
end
