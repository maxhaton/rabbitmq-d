module kaleidic.api.rabbitmq.examples.bind;
import std.stdio;
import std.string;

import kaleidic.api.rabbitmq.rabbitmq;
import utils;

int main(string[] args)
{
  char const *hostname;
  int port, status;
  char const *queuename;
  amqp_socket_t *socket;
  amqp_connection_state_t conn;

  if (argc < 4) {
    fprintf(stderr, "Usage: amqps_listenq host port queuename "
            "[cacert.pem [verifypeer] [verifyhostname] [key.pem cert.pem]]\n");
    return 1;
  }

  hostname = argv[1];
  port = atoi(argv[2]);
  queuename = argv[3];

  conn = amqp_new_connection();

  socket = amqp_ssl_socket_new(conn);
  if (!socket) {
    die("creating SSL/TLS socket");
  }

  amqp_ssl_socket_set_verify_peer(socket, 0);
  amqp_ssl_socket_set_verify_hostname(socket, 0);

  if (argc > 4) {
    int nextarg = 5;
    status = amqp_ssl_socket_set_cacert(socket, argv[4]);
    if (status) {
      die("setting CA certificate");
    }
    if (argc > nextarg && !strcmp("verifypeer", argv[nextarg])) {
      amqp_ssl_socket_set_verify_peer(socket, 1);
      nextarg++;
    }
    if (argc > nextarg && !strcmp("verifyhostname", argv[nextarg])) {
      amqp_ssl_socket_set_verify_hostname(socket, 1);
      nextarg++;
    }
    if (argc > nextarg + 1) {
      status =
          amqp_ssl_socket_set_key(socket, argv[nextarg + 1], argv[nextarg]);
      if (status) {
        die("setting client cert");
      }
    }
  }


  status = amqp_socket_open(socket, hostname, port);
  if (status) {
    die("opening SSL/TLS connection");
  }

  die_on_amqp_error(amqp_login(conn, "/", 0, 131072, 0, AMQP_SASL_METHOD_PLAIN, "guest", "guest"),
                    "Logging in");
  amqp_channel_open(conn, 1);
  die_on_amqp_error(amqp_get_rpc_reply(conn), "Opening channel");

  amqp_basic_consume(conn, 1, amqp_cstring_bytes(queuename), amqp_empty_bytes, 0, 0, 0, amqp_empty_table);
  die_on_amqp_error(amqp_get_rpc_reply(conn), "Consuming");

  {
    for (;;) {
      amqp_rpc_reply_t res;
      amqp_envelope_t envelope;

      amqp_maybe_release_buffers(conn);

      res = amqp_consume_message(conn, &envelope, NULL, 0);

      if (AMQP_RESPONSE_NORMAL != res.reply_type) {
        break;
      }

      printf("Delivery %u, exchange %.*s routingkey %.*s\n",
             (unsigned) envelope.delivery_tag,
             (int) envelope.exchange.len, (char *) envelope.exchange.bytes,
             (int) envelope.routing_key.len, (char *) envelope.routing_key.bytes);

      if (envelope.message.properties._flags & AMQP_BASIC_CONTENT_TYPE_FLAG) {
        printf("Content-type: %.*s\n",
               (int) envelope.message.properties.content_type.len,
               (char *) envelope.message.properties.content_type.bytes);
      }
      printf("----\n");

      amqp_dump(envelope.message.body.bytes, envelope.message.body.len);

      amqp_destroy_envelope(&envelope);
    }
  }

  die_on_amqp_error(amqp_channel_close(conn, 1, AMQP_REPLY_SUCCESS), "Closing channel");
  die_on_amqp_error(amqp_connection_close(conn, AMQP_REPLY_SUCCESS), "Closing connection");
  die_on_error(amqp_destroy_connection(conn), "Ending connection");

  return 0;
}