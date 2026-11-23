package com.example.todo;

public record Item(int id, String text, Priority priority, boolean done) {

    public Item markDone() {
        return new Item(id, text, priority, true);
    }
}
