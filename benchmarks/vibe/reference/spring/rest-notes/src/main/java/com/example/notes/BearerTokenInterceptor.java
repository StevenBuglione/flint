package com.example.notes;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.Optional;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.HandlerInterceptor;

/** Resolves `Authorization: Bearer <token>` to the user, as the request attribute `userId`, or answers 401. */
@Component
public class BearerTokenInterceptor implements HandlerInterceptor {

    public static final String USER_ID = "userId";

    private final UserRepository users;

    public BearerTokenInterceptor(UserRepository users) {
        this.users = users;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        String header = Optional.ofNullable(request.getHeader("Authorization")).orElse("");
        if (!header.startsWith("Bearer ") || header.length() == "Bearer ".length()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "missing bearer token");
        }
        long user = users.findUserByToken(header.substring("Bearer ".length()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "invalid token"));
        request.setAttribute(USER_ID, user);
        return true;
    }
}
